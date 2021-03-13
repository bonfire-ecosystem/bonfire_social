defmodule Bonfire.Social.Web.PostLive do
  use Bonfire.Web, {:live_view, [layout: {Bonfire.Web.LayoutView, "thread.html"}]}
  alias Bonfire.Fake
  alias Bonfire.Web.LivePlugs
  alias Bonfire.Me.Users
  alias Bonfire.Me.Web.{CreateUserLive, LoggedDashboardLive}
  import Bonfire.Me.Integration

  @thread_max_depth 3 # TODO: put in config

  def mount(params, session, socket) do
    LivePlugs.live_plug(params, session, socket, [
      LivePlugs.LoadCurrentAccount,
      LivePlugs.LoadCurrentUser,
      # LivePlugs.LoadCurrentAccountUsers,
      LivePlugs.StaticChanged,
      LivePlugs.Csrf,
      &mounted/3
    ])
  end

  defp mounted(params, session, socket) do

    with {:ok, post} <- Bonfire.Social.Posts.read(Map.get(params, "post_id"), e(socket, :assigns, :current_user, nil)) do
      # IO.inspect(post, label: "the post:")

      {activity, object} = Map.pop(post, :activity)

      {:ok,
      socket
      |> assign(
        page_title: "Post",
        activity: activity,
        object: object
      )}

    else _e ->
      {:error, "Not found"}
    end


  end

  # def handle_params(%{"tab" => tab} = _params, _url, socket) do
  #   {:noreply,
  #    assign(socket,
  #      selected_tab: tab
  #    )}
  # end

  # def handle_params(%{} = _params, _url, socket) do
  #   {:noreply,
  #    assign(socket,
  #      current_user: Fake.user_live()
  #    )}
  # end

  defdelegate handle_event(action, attrs, socket), to: Bonfire.Web.LiveHandler
  defdelegate handle_info(info, socket), to: Bonfire.Web.LiveHandler

end
