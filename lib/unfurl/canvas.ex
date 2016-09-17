defmodule CanvasAPI.Unfurl.Canvas do
  @canvas_regex Regex.compile!("\\Ahttps?://#{System.get_env("WEB_HOST")}/[^/]+/(?<id>[^/]{22})/[^/]+\\z")

  alias CanvasAPI.{Canvas, Repo}
  alias CanvasAPI.Unfurl.Field

  def unfurl(url) do
    with id when is_binary(id) <- extract_canvas_id(url),
         canvas when not is_nil(canvas) <- Repo.get(Canvas, id) do
      %CanvasAPI.Unfurl{
        id: url,
        title: canvas_title(canvas),
        text: canvas_summary(canvas),
        provider_name: "Canvas",
        provider_url: "https://usecanvas.com",
        fields: [
          progress_field(canvas)
        ]
      }
    end
  end

  def canvas_regex, do: @canvas_regex

  defp canvas_summary(canvas) do
    first_content_block =
      canvas.blocks
      |> Enum.at(1)

    case first_content_block do
      %{"blocks" => [block | _]} ->
        block["content"]
      %{"content" => content} ->
        String.slice(content, 0..140)
    end
  end

  defp canvas_title(canvas) do
    canvas.blocks
    |> Enum.at(0)
    |> Map.get("content")
  end

  defp progress_field(canvas) do
    {complete, total} = do_progress_field(canvas.blocks)
    progress = if total > 0, do: (complete / total * 100) |> Float.round(2)
    %Field{title: "progress", value: progress, short: true}
  end

  defp do_progress_field(blocks, progress \\ {0, 0}) do
    blocks
    |> Enum.reduce(progress, fn
      (%{"blocks" => child_blocks}, progress) ->
        do_progress_field(child_blocks, progress)
      (block = %{"type" => "checklist-item"}, progress) ->
        if get_in(block, ~w(meta checked)) do
          {elem(progress, 0) + 1, elem(progress, 1) + 1}
        else
          {elem(progress, 0), elem(progress, 1) + 1}
        end
      (_, progress) ->
        progress
    end)
  end

  defp extract_canvas_id(url) do
    with match when is_map(match) <- Regex.named_captures(@canvas_regex, url) do
      match["id"]
    end
  end
end