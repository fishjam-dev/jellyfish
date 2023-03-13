defmodule JellyfishWeb.ComponentController do
  use JellyfishWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Jellyfish.Component
  alias Jellyfish.Room
  alias Jellyfish.RoomService
  alias JellyfishWeb.ApiSpec
  alias OpenApiSpex.{Response, Schema}

  action_fallback JellyfishWeb.FallbackController

  operation :create,
    summary: "Creates the component and adds it to the room",
    parameters: [
      room_id: [
        in: :path,
        type: :string,
        description: "Room ID"
      ]
    ],
    request_body:
      {"Component config", "application/json",
       %Schema{
         type: :object,
         properties: %{
           options: ApiSpec.Component.Options,
           type: ApiSpec.Component.Type
         },
         required: [:type]
       }},
    responses: [
      created: {"Successfully added component", "application/json", ApiSpec.Component},
      bad_request: %Response{description: "Invalid request"},
      not_found: %Response{description: "Room doesn't exist"}
    ]

  operation :delete,
    summary: "Delete the component from the room",
    parameters: [
      room_id: [
        in: :path,
        type: :string,
        description: "Room ID"
      ],
      id: [
        in: :path,
        type: :string,
        description: "Component ID"
      ]
    ],
    responses: [
      no_content: %Response{description: "Successfully deleted"},
      not_found: %Response{description: "Either component or the room doesn't exist"}
    ]

  def create(conn, %{"room_id" => room_id} = params) do
    with component_options <- Map.get(params, "options"),
         {:ok, component_type_string} <- Map.fetch(params, "type"),
         {:ok, component_type} <- Component.parse_type(component_type_string),
         {:ok, room_pid} <- RoomService.find_room(room_id),
         {:ok, component} <- Room.add_component(room_pid, component_type, component_options) do
      conn
      |> put_resp_content_type("application/json")
      |> put_status(:created)
      |> render("show.json", component: component)
    else
      :error -> {:error, :bad_request, "Invalid request body structure"}
      {:error, :invalid_type} -> {:error, :bad_request, "Invalid component type"}
      {:error, :room_not_found} -> {:error, :not_found, "Room #{room_id} does not exist"}
    end
  end

  def delete(conn, %{"room_id" => room_id, "id" => id}) do
    with {:ok, room_pid} <- RoomService.find_room(room_id),
         :ok <- Room.remove_component(room_pid, id) do
      send_resp(conn, :no_content, "")
    else
      {:error, :room_not_found} -> {:error, :not_found, "Room #{room_id} does not exist"}
      {:error, :component_not_found} -> {:error, :not_found, "Component #{id} does not exist"}
    end
  end
end
