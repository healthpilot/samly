defmodule Samly.Router do
  @moduledoc false

  use Plug.Router

  plug :secure_samly
  plug :match
  plug :dispatch

  forward("/auth", to: Samly.AuthRouter)
  forward("/sp", to: Samly.SPRouter)
  forward("/csp-report", to: Samly.CsprRouter)

  match _ do
    conn |> send_resp(404, "not_found")
  end

  @frame_ancestors Application.get_env(:samly, :allowed_frame_ancestors)

  @csp """
       default-src 'none';
       script-src 'self' 'nonce-<%= nonce %>' 'report-sample';
       img-src 'self' 'report-sample';
       report-to /sso/csp-report;
       """
       |> then(fn csp ->
            case @frame_ancestors do
              [_ | _] -> csp <> " frame-ancestors #{Enum.join(@frame_ancestors, " ")};"
              _ -> csp
            end
          end)
       |> String.replace("\n", " ")

  defp secure_samly(conn, _opts) do
    conn
    |> put_private(:samly_nonce, :crypto.strong_rand_bytes(18) |> Base.encode64())
    |> register_before_send(fn connection ->
      nonce = connection.private[:samly_nonce]

      connection
      |> put_resp_header("cache-control", "no-cache, no-store, must-revalidate")
      |> put_resp_header("pragma", "no-cache")
      |> put_resp_header("content-security-policy", EEx.eval_string(@csp, nonce: nonce))
      |> put_resp_header("x-xss-protection", "1; mode=block")
      |> put_resp_header("x-content-type-options", "nosniff")
      |> then(fn c ->
          cond do
            @frame_ancestors -> c
            true -> put_resp_header(c, "x-frame-options", "SAMEORIGIN")
          end
        end)
    end)
  end
end
