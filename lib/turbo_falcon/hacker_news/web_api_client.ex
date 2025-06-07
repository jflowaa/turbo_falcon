defmodule TurboFalcon.HackerNews.WebApiClient do
  @base_url "https://hacker-news.firebaseio.com/v0/"

  def new(pool_size \\ 100) do
    unless Process.whereis(__MODULE__) do
      {:ok, _} =
        Finch.start_link(
          name: __MODULE__,
          pools: %{
            default: [
              size: pool_size
            ]
          }
        )
    end

    Req.new(
      base_url: @base_url,
      receive_timeout: 30_000,
      finch: __MODULE__
    )
  end

  def get_item_by_id(client, id) do
    Req.get(client,
      url: "item/#{id}.json"
    )
  end

  def get_who_is_hiring_user(client) do
    Req.get(client,
      url: "user/whoishiring.json"
    )
  end
end
