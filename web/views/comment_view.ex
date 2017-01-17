defmodule CanvasAPI.CommentView do
  @moduledoc """
  A view for rendering comments.
  """

  use CanvasAPI.Web, :view

  def render("show.json", %{comment: comment}) do
    %{
      data: render_one(comment, __MODULE__, "comment.json")
    }
  end

  def render("comment.json", %{comment: comment}) do
    %{
      id: comment.id,
      attributes: %{
        blocks: comment.blocks
      },
      relationships: %{
        block: %{data: %{id: comment.block_id, type: "block"}},
        canvas: %{data: %{id: comment.canvas_id, type: "canvas"}},
        creator: %{data: %{id: comment.creator_id, type: "user"}}
      },
      type: "comment"
    }
  end
end
