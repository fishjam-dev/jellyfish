defmodule JellyfishWeb.RecordingContentController do
  use JellyfishWeb, :controller
  use OpenApiSpex.ControllerSpecs

  require Logger

  alias Jellyfish.Component.HLS.RequestHandler
  alias JellyfishWeb.ApiSpec

  alias Plug.Conn

  action_fallback JellyfishWeb.FallbackController

  @playlist_content_type "application/vnd.apple.mpegurl"
  @recording_id_spec [in: :path, description: "Recording id", type: :string]

  tags [:recording]

  operation :index,
    operation_id: "getRecordingContent",
    summary: "Retrieve Recording (HLS) Content",
    parameters: [
      recording_id: @recording_id_spec,
      filename: [in: :path, description: "Name of the file", type: :string]
    ],
    required: [:recording_id, :filename],
    responses: [
      ok: ApiSpec.data("File was found", ApiSpec.HLS.Response),
      not_found: ApiSpec.error("File not found"),
      bad_request: ApiSpec.error("Invalid request")
    ]

  def index(conn, %{"recording_id" => recording_id, "filename" => filename}) do
    with {:ok, file} <-
           RequestHandler.handle_recording_request(recording_id, filename) do
      conn =
        if String.ends_with?(filename, ".m3u8"),
          do: put_resp_content_type(conn, @playlist_content_type, nil),
          else: conn

      Conn.send_resp(conn, 200, file)
    else
      {:error, :invalid_recording} ->
        {:error, :bad_request, "Invalid recording, got: #{recording_id}"}

      {:error, :invalid_path} ->
        {:error, :bad_request, "Invalid filename, got: #{filename}"}

      {:error, _reason} ->
        {:error, :not_found, "File not found"}
    end
  end
end
