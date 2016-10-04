defmodule CanvasAPI.CanvasController do
  use CanvasAPI.Web, :controller

  alias CanvasAPI.{Canvas, ChangesetView, ErrorView, Repo, User}

  plug CanvasAPI.CurrentAccountPlug when not action in [:show]
  plug :ensure_team when not action in [:show]
  plug :ensure_user when not action in [:show]
  plug :ensure_canvas when action in [:update]

  def create(conn, params) do
    %Canvas{}
    |> Canvas.changeset(get_in(params, ~w(data attributes)) || %{})
    |> put_assoc(:creator, conn.private.current_user)
    |> put_assoc(:team, conn.private.current_team)
    |> Canvas.put_template(
         get_in(params, ~w(data relationships template data)))
    |> Repo.insert
    |> case do
      {:ok, canvas} ->
        conn
        |> put_status(:created)
        |> render("show.json", canvas: Repo.preload(canvas, creator: [:team]))
      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> render(ChangesetView, "error.json", changeset: changeset)
    end
  end

  def index(conn, _params) do
    canvases =
      from(assoc(conn.private.current_user, :canvases),
           preload: [creator: [:team]])
      |> Repo.all

    render(conn, "index.json", canvases: canvases)
  end

  def index_templates(conn, _params) do
    templates =
      from(assoc(conn.private.current_user, :canvases),
           where: [is_template: true],
           preload: [creator: [:team]])
      |> Repo.all
      |> merge_global_templates
      |> Enum.sort_by(&Canvas.title/1)

    render(conn, "index.json", canvases: templates)
  end

  def show(conn, params = %{"id" => id, "team_id" => team_id}) do
    from(Canvas, where: [team_id: ^team_id], preload: [creator: [:team]])
    |> Repo.get(id)
    |> case do
      canvas = %Canvas{} ->
        render_show(conn, canvas, params["trailing_format"])
      nil ->
        conn
        |> put_status(:not_found)
        |> render(ErrorView, "404.json")
    end
  end

  def update(conn, params) do
    conn.private.canvas
    |> Canvas.update_changeset(get_in(params, ~w(data attributes)))
    |> Repo.update
    |> case do
      {:ok, canvas} ->
        notify_channels(conn,
          conn.private.canvas.slack_channel_ids,
          get_in(params, ~w(data attributes slack_channel_ids)))
        render_show(conn, canvas)
      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> render(ChangesetView, "error.json", changeset: changeset)
    end
  end

  def delete(conn, %{"id" => id}) do
    assoc(conn.private.current_team, :canvases)
    |> Repo.get(id)
    |> case do
      canvas = %Canvas{} ->
        Repo.delete!(canvas)
        send_resp(conn, :no_content, "")
      _ ->
        conn
        |> put_status(:not_found)
        |> render(ErrorView, "404.json")
    end
  end

  defp notify_channels(conn, old_channel_ids, new_channel_ids) do
    token =
      assoc(conn.private.current_team, :oauth_tokens)
      |> first
      |> Repo.one
      |> Map.get(:meta)
      |> get_in(~w(bot bot_access_token))

    (new_channel_ids -- old_channel_ids)
    |> Enum.each(&(notify_channel(conn, token, &1)))
  end

  defp notify_channel(conn, token, channel_id) do
    %{canvas: canvas, current_user: user, current_team: team} = conn.private

    author_email_hash =
      :crypto.hash(:md5, String.downcase(canvas.creator.email))
      |> Base.encode16(case: :lower)

    text =
      "#{user.name} posted a new canvas to this channel."

    Slack.client(token)
    |> Slack.Chat.postMessage(
      channel: channel_id,
      text: text,
      attachments: Poison.encode!([%{
        author_name: canvas.creator.name,
        author_icon: "https://www.gravatar.com/avatar/#{author_email_hash}",
        title: Canvas.title(canvas),
        title_link: "#{System.get_env("WEB_URL")}/#{team.domain}/#{canvas.id}",
        text: Canvas.summary(canvas)
      }]))
  end

  defp ensure_canvas(conn, _opts) do
    if canvas = Repo.get(Canvas, conn.params["id"]) do
      put_private(conn, :canvas, Repo.preload(canvas, creator: [:team]))
    else
      conn
      |> halt
      |> put_status(:not_found)
      |> render(ErrorView, "404.json")
    end
  end

  defp render_show(conn, canvas, format \\ "json")

  defp render_show(conn, canvas, "canvas") do
    conn
    |> put_resp_header("content-type", "application/octet-stream")
    |> render("canvas.json", canvas: canvas, json_api: false)
  end

  defp render_show(conn, canvas, _) do
    render(conn, "show.json", canvas: canvas)
  end

  defp merge_global_templates(team_templates) do
    do_merge_global_templates(
      team_templates, System.get_env("TEMPLATE_USER_ID"))
  end

  defp do_merge_global_templates(templates, nil), do: templates
  defp do_merge_global_templates(templates, id) do
    templates ++
      (from(c in Canvas,
           join: u in User, on: u.id == c.creator_id,
           where: u.id == ^id,
           where: c.is_template == true,
           preload: [creator: [:team]])
      |> Repo.all)
  end
end
