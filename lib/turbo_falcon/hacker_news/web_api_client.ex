defmodule TurboFalcon.HackerNews.WebApiClient do
  @base_url "https://hacker-news.firebaseio.com/v0/"

  def new do
    Req.new(
      base_url: @base_url,
      receive_timeout: 30_000,
      finch: TurboFalcon.HackerNews.Finch
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
