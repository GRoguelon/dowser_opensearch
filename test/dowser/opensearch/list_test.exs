defmodule Dowser.Opensearch.ListTest do
  use ExUnit.Case, async: false

  alias Dowser.Opensearch.Error
  alias Dowser.Opensearch.HTTPStub
  alias Dowser.Opensearch.List, as: ListApi

  @page ~s({"next_token":"dG9rZW4=","indices":[{"index":"posts","health":"green","docs.count":"42"}]})
  @page_response "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: #{byte_size(@page)}\r\n\r\n" <>
                   @page

  @help_text "=^.^=\n/_list/indices\n/_list/indices/{index}\n/_list/shards\n/_list/shards/{index}\n"
  @help_response "HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nContent-Length: #{byte_size(@help_text)}\r\n\r\n" <>
                   @help_text

  @server_error ~s({"message":"boom"})
  @server_error_response "HTTP/1.1 500 Internal Server Error\r\nContent-Type: application/json\r\nContent-Length: #{byte_size(@server_error)}\r\n\r\n" <>
                           @server_error

  describe "help/1" do
    test "GETs /_list and parses the endpoint lines, dropping the banner" do
      {port, server} = start_server(@help_response)

      assert {:ok, endpoints} = ListApi.help(context: context(port))

      assert endpoints == [
               "/_list/indices",
               "/_list/indices/{index}",
               "/_list/shards",
               "/_list/shards/{index}"
             ]

      req = Task.await(server)
      assert req.method == "GET"
      assert req.path == "/_list"
    end

    test "help!/1 returns the endpoints directly" do
      {port, server} = start_server(@help_response)

      assert ["/_list/indices" | _] = ListApi.help!(context: context(port))

      Task.await(server)
    end

    test "passes an error through instead of parsing it" do
      {port, server} = start_server(@server_error_response)

      assert {:error, %Error{status: 500}} = ListApi.help(context: context(port))

      Task.await(server)
    end
  end

  describe "indices/1" do
    test "GETs /_list/indices and decodes the page" do
      {port, server} = start_server(@page_response)

      assert {:ok, body} = ListApi.indices(context: context(port))
      assert body["next_token"] == "dG9rZW4="
      assert [%{"index" => "posts"}] = body["indices"]

      req = Task.await(server)
      assert req.method == "GET"
      assert req.path == "/_list/indices"
    end

    test "appends the index target after the endpoint" do
      {port, server} = start_server(@page_response)

      assert {:ok, _} = ListApi.indices(index: "posts*", context: context(port))
      assert Task.await(server).path == "/_list/indices/posts*"
    end

    test "joins several indices with commas" do
      {port, server} = start_server(@page_response)

      assert {:ok, _} = ListApi.indices(index: ["posts", "comments"], context: context(port))
      assert Task.await(server).path == "/_list/indices/posts,comments"
    end

    test "forwards the paging params" do
      {port, server} = start_server(@page_response)

      assert {:ok, _} =
               ListApi.indices(
                 params: [size: 100, next_token: "dG9rZW4="],
                 context: context(port)
               )

      assert Task.await(server).path == "/_list/indices?size=100&next_token=dG9rZW4%3D"
    end
  end

  describe "shards/1" do
    test "GETs /_list/shards" do
      {port, server} = start_server(@page_response)

      assert {:ok, _} = ListApi.shards(context: context(port))

      req = Task.await(server)
      assert req.method == "GET"
      assert req.path == "/_list/shards"
    end

    test "appends the index target" do
      {port, server} = start_server(@page_response)

      assert {:ok, _} = ListApi.shards(index: "posts", context: context(port))
      assert Task.await(server).path == "/_list/shards/posts"
    end

    test "shards!/1 raises the error exception" do
      {port, server} = start_server(@server_error_response)

      assert_raise Error, fn -> ListApi.shards!(context: context(port)) end

      Task.await(server)
    end
  end

  defp context(port), do: HTTPStub.context(port)

  defp start_server(response), do: HTTPStub.start_server(response)
end
