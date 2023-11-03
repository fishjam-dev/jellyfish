defmodule JellyfishWeb.ComponentControllerTest do
  use JellyfishWeb.ConnCase

  import OpenApiSpex.TestAssertions

  alias Jellyfish.Component.HLS

  @schema JellyfishWeb.ApiSpec.spec()
  @source_uri "rtsp://placeholder-19inrifjbsjb.it:12345/afwefae"

  setup %{conn: conn} do
    server_api_token = Application.fetch_env!(:jellyfish, :server_api_token)
    conn = put_req_header(conn, "authorization", "Bearer " <> server_api_token)
    conn = put_req_header(conn, "accept", "application/json")

    conn = post(conn, ~p"/room")
    assert %{"id" => id} = json_response(conn, :created)["data"]["room"]

    on_exit(fn ->
      conn = delete(conn, ~p"/room/#{id}")
      assert response(conn, :no_content)
    end)

    {:ok, %{conn: conn, room_id: id}}
  end

  describe "create component" do
    test "renders errors when component type is invalid", %{conn: conn, room_id: room_id} do
      conn = post(conn, ~p"/room/#{room_id}/component", type: "invalid_type")

      assert json_response(conn, :bad_request)["errors"] == "Invalid component type"
    end

    test "renders errors when room doesn't exists", %{conn: conn} do
      room_id = "abc"
      conn = post(conn, ~p"/room/#{room_id}/component", type: "hls")
      assert json_response(conn, :not_found)["errors"] == "Room #{room_id} does not exist"
    end
  end

  describe "create hls component" do
    test "renders component when data is valid, allows max 1 hls per room", %{conn: conn} do
      conn = post(conn, ~p"/room", videoCodec: "h264")
      assert %{"id" => room_id} = json_response(conn, :created)["data"]["room"]

      conn = post(conn, ~p"/room/#{room_id}/component", type: "hls")

      assert response =
               %{
                 "data" => %{
                   "id" => id,
                   "type" => "hls",
                   "metadata" => %{
                     "playable" => false,
                     "lowLatency" => false,
                     "persistent" => false,
                     "targetWindowDuration" => nil
                   }
                 }
               } =
               json_response(conn, :created)

      assert_response_schema(response, "ComponentDetailsResponse", @schema)

      assert_hls_path(room_id, persistent: false)

      conn = get(conn, ~p"/room/#{room_id}")

      assert %{
               "id" => ^room_id,
               "components" => [
                 %{"id" => ^id, "type" => "hls"}
               ]
             } = json_response(conn, :ok)["data"]

      # Try to add another hls component
      conn = post(conn, ~p"/room/#{room_id}/component", type: "hls")

      assert json_response(conn, :bad_request)["errors"] ==
               "Reached components limit in room #{room_id}"

      conn = delete(conn, ~p"/room/#{room_id}")
      assert response(conn, :no_content)
      assert_no_hls_path(room_id)
    end

    test "renders component with peristent enabled", %{conn: conn} do
      conn = post(conn, ~p"/room", videoCodec: "h264")
      assert %{"id" => room_id} = json_response(conn, :created)["data"]["room"]

      conn = post(conn, ~p"/room/#{room_id}/component", type: "hls", options: %{persistent: true})

      assert response =
               %{
                 "data" => %{
                   "type" => "hls",
                   "metadata" => %{
                     "playable" => false,
                     "lowLatency" => false,
                     "persistent" => true,
                     "targetWindowDuration" => nil
                   }
                 }
               } =
               json_response(conn, :created)

      assert_response_schema(response, "ComponentDetailsResponse", @schema)
      assert_hls_path(room_id, persistent: true)

      # It is persistent stream so we have to remove it manually
      assert {:ok, _removed_files} = room_id |> HLS.Recording.directory() |> File.rm_rf()
    end

    test "renders component with targetWindowDuration set", %{conn: conn} do
      conn = post(conn, ~p"/room", videoCodec: "h264")
      assert %{"id" => room_id} = json_response(conn, :created)["data"]["room"]

      conn =
        post(conn, ~p"/room/#{room_id}/component",
          type: "hls",
          options: %{targetWindowDuration: 10}
        )

      assert response =
               %{
                 "data" => %{
                   "type" => "hls",
                   "metadata" => %{
                     "playable" => false,
                     "lowLatency" => false,
                     "persistent" => false,
                     "targetWindowDuration" => 10
                   }
                 }
               } =
               json_response(conn, :created)

      assert_response_schema(response, "ComponentDetailsResponse", @schema)

      conn = delete(conn, ~p"/room/#{room_id}")
      assert response(conn, :no_content)
      assert_no_hls_path(room_id)
    end

    test "renders component with ll-hls enabled", %{conn: conn} do
      conn = post(conn, ~p"/room", videoCodec: "h264")
      assert %{"id" => room_id} = json_response(conn, :created)["data"]["room"]

      assert Registry.lookup(Jellyfish.RequestHandlerRegistry, room_id) |> Enum.empty?()

      conn = post(conn, ~p"/room/#{room_id}/component", type: "hls", options: %{lowLatency: true})

      assert response =
               %{
                 "data" => %{
                   "id" => id,
                   "type" => "hls",
                   "metadata" => %{"playable" => false, "lowLatency" => true}
                 }
               } =
               json_response(conn, :created)

      assert_response_schema(response, "ComponentDetailsResponse", @schema)

      conn = get(conn, ~p"/room/#{room_id}")

      assert %{
               "id" => ^room_id,
               "components" => [
                 %{"id" => ^id, "type" => "hls"}
               ]
             } = json_response(conn, :ok)["data"]

      [{request_handler, _value}] = Registry.lookup(Jellyfish.RequestHandlerRegistry, room_id)
      assert Process.alive?(request_handler)
      Process.monitor(request_handler)

      {:ok, %{engine_pid: engine_pid}} = Jellyfish.RoomService.get_room(room_id)
      assert Process.alive?(request_handler)
      Process.monitor(engine_pid)

      conn = delete(conn, ~p"/room/#{room_id}")
      assert response(conn, :no_content)
      assert_no_hls_path(room_id)

      # Engine can terminate up to around 5 seconds
      # Hls endpoint tries to process all streams to the end before termination
      # It has 5 seconds for it
      assert_receive {:DOWN, _ref, :process, ^engine_pid, :normal}, 10_000
      assert_receive {:DOWN, _ref, :process, ^request_handler, :normal}

      assert Registry.lookup(Jellyfish.RequestHandlerRegistry, room_id) |> Enum.empty?()
    end

    test "renders errors when request body structure is invalid", %{conn: conn, room_id: room_id} do
      conn = post(conn, ~p"/room/#{room_id}/component", invalid_parameter: "hls")

      assert json_response(conn, :bad_request)["errors"] == "Invalid request body structure"
    end

    test "renders errors when video codec is different than h264", %{conn: conn, room_id: room_id} do
      conn = post(conn, ~p"/room/#{room_id}/component", type: "hls")

      assert json_response(conn, :bad_request)["errors"] ==
               "Incompatible video codec enforced in room #{room_id}"
    end
  end

  describe "create rtsp component" do
    test "renders component with required options", %{conn: conn, room_id: room_id} do
      conn =
        post(conn, ~p"/room/#{room_id}/component",
          type: "rtsp",
          options: %{sourceUri: @source_uri}
        )

      assert response =
               %{
                 "data" => %{
                   "id" => id,
                   "type" => "rtsp",
                   "metadata" => %{}
                 }
               } =
               json_response(conn, :created)

      assert_response_schema(response, "ComponentDetailsResponse", @schema)

      conn = get(conn, ~p"/room/#{room_id}")

      assert %{
               "id" => ^room_id,
               "components" => [
                 %{"id" => ^id, "type" => "rtsp"}
               ]
             } = json_response(conn, :ok)["data"]
    end

    test "renders errors when component requires options not present in request", %{
      conn: conn,
      room_id: room_id
    } do
      conn = post(conn, ~p"/room/#{room_id}/component", type: "rtsp")

      assert json_response(conn, :bad_request)["errors"] == "Invalid request body structure"
    end
  end

  describe "delete component" do
    setup [:create_rtsp_component]

    test "deletes chosen component", %{conn: conn, room_id: room_id, component_id: component_id} do
      conn = delete(conn, ~p"/room/#{room_id}/component/#{component_id}")

      assert response(conn, :no_content)

      conn = get(conn, ~p"/room/#{room_id}")

      assert %{
               "id" => ^room_id,
               "components" => []
             } = json_response(conn, :ok)["data"]
    end

    test "deletes not existing component", %{conn: conn, room_id: room_id} do
      component_id = "test123"
      conn = delete(conn, ~p"/room/#{room_id}/component/#{component_id}")

      assert json_response(conn, :not_found)["errors"] ==
               "Component #{component_id} does not exist"
    end

    test "deletes component from not exisiting room", %{conn: conn, component_id: component_id} do
      room_id = "abc"
      conn = delete(conn, ~p"/room/#{room_id}/component/#{component_id}")
      assert json_response(conn, :not_found)["errors"] == "Room #{room_id} does not exist"
    end
  end

  defp create_rtsp_component(state) do
    conn =
      post(state.conn, ~p"/room/#{state.room_id}/component",
        type: "rtsp",
        options: %{sourceUri: @source_uri}
      )

    assert %{"id" => id} = json_response(conn, :created)["data"]

    %{component_id: id}
  end

  defp assert_hls_path(room_id, persistent: persistent) do
    hls_path = HLS.output_dir(room_id, persistent: persistent)
    assert {:ok, ^hls_path} = HLS.EtsHelper.get_hls_folder_path(room_id)
  end

  defp assert_no_hls_path(room_id) do
    assert {:error, :room_not_found} = HLS.EtsHelper.get_hls_folder_path(room_id)
  end
end
