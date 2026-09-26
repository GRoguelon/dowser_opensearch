defmodule Dowser.Opensearch.IndexTest do
  use ExUnit.Case, async: false

  alias Dowser.Opensearch.Error
  alias Dowser.Opensearch.HTTPStub
  alias Dowser.Opensearch.Index

  @server_error ~s({"message":"boom"})
  @server_error_response "HTTP/1.1 500 Internal Server Error\r\nContent-Type: application/json\r\nContent-Length: #{byte_size(@server_error)}\r\n\r\n" <>
                           @server_error

  describe "create_index/3" do
    test "PUTs the body to /{index}" do
      {port, server} = start_server()

      body = %{"settings" => %{"number_of_shards" => 3}}
      assert {:ok, _} = Index.create_index(body, "posts", context: context(port))

      req = Task.await(server)
      assert req.method == "PUT"
      assert req.path == "/posts"
      assert req.body == ~s({"settings":{"number_of_shards":3}})
    end

    test "sends an empty body when given one" do
      {port, server} = start_server()

      assert {:ok, _} = Index.create_index(%{}, "posts", context: context(port))
      assert Task.await(server).body == "{}"
    end

    test "requires an index" do
      assert {:error, %ArgumentError{} = error} = Index.create_index(%{}, nil)
      assert Exception.message(error) =~ "requires an index"
    end

    test "create_index!/3 raises when the index is missing" do
      assert_raise ArgumentError, ~r/requires an index/, fn ->
        Index.create_index!(%{}, nil)
      end
    end
  end

  describe "get_index/2" do
    test "GETs /{index}" do
      {port, server} = start_server()

      assert {:ok, _} = Index.get_index("posts", context: context(port))

      req = Task.await(server)
      assert req.method == "GET"
      assert req.path == "/posts"
    end

    test "joins several indices with commas" do
      {port, server} = start_server()

      assert {:ok, _} = Index.get_index(["posts", "comments"], context: context(port))
      assert Task.await(server).path == "/posts,comments"
    end

    test "URL-encodes an index name" do
      {port, server} = start_server()

      assert {:ok, _} = Index.get_index("my posts", context: context(port))
      assert Task.await(server).path == "/my%20posts"
    end
  end

  describe "delete_index/2" do
    test "DELETEs /{index}" do
      {port, server} = start_server()

      assert {:ok, _} = Index.delete_index("posts", context: context(port))

      req = Task.await(server)
      assert req.method == "DELETE"
      assert req.path == "/posts"
    end

    test "requires an index" do
      assert {:error, %ArgumentError{}} = Index.delete_index(nil)
    end
  end

  describe "index_exists/2" do
    test "HEADs /{index} and returns true on a 2xx" do
      {port, server} = start_server(HTTPStub.head_response(200))

      assert Index.index_exists("posts", context: context(port)) == {:ok, true}

      req = Task.await(server)
      assert req.method == "HEAD"
      assert req.path == "/posts"
    end

    test "returns false on a 404" do
      {port, server} = start_server(HTTPStub.head_response(404))

      assert Index.index_exists("missing", context: context(port)) == {:ok, false}

      Task.await(server)
    end

    test "index_exists?/2 returns the bare boolean" do
      {port, server} = start_server(HTTPStub.head_response(200))

      assert Index.index_exists?("posts", context: context(port)) == true

      Task.await(server)
    end

    test "index_exists?/2 raises on a genuine error rather than returning false" do
      {port, server} = start_server(@server_error_response)

      assert_raise Error, fn -> Index.index_exists?("posts", context: context(port)) end

      Task.await(server)
    end
  end

  describe "open/2 and close/2" do
    test "open/2 POSTs /{index}/_open" do
      {port, server} = start_server()

      assert {:ok, _} = Index.open("posts", context: context(port))

      req = Task.await(server)
      assert req.method == "POST"
      assert req.path == "/posts/_open"
    end

    test "close/2 POSTs /{index}/_close" do
      {port, server} = start_server()

      assert {:ok, _} = Index.close("posts", context: context(port))

      req = Task.await(server)
      assert req.method == "POST"
      assert req.path == "/posts/_close"
    end
  end

  describe "add_block/3" do
    test "PUTs /{index}/_block/{block}" do
      {port, server} = start_server()

      assert {:ok, _} = Index.add_block("posts", "write", context: context(port))

      req = Task.await(server)
      assert req.method == "PUT"
      assert req.path == "/posts/_block/write"
    end

    test "requires a block, naming it in the error" do
      assert {:error, %ArgumentError{} = error} = Index.add_block("posts", nil)
      assert Exception.message(error) =~ "block is required"
    end

    test "requires an index" do
      assert {:error, %ArgumentError{} = error} = Index.add_block(nil, "write")
      assert Exception.message(error) =~ "requires an index"
    end
  end

  describe "clone/4, shrink/4 and split/4" do
    test "clone/4 POSTs /{index}/_clone/{target}" do
      {port, server} = start_server()

      assert {:ok, _} = Index.clone(%{}, "posts", "posts-copy", context: context(port))

      req = Task.await(server)
      assert req.method == "POST"
      assert req.path == "/posts/_clone/posts-copy"
    end

    test "shrink/4 POSTs /{index}/_shrink/{target}" do
      {port, server} = start_server()

      assert {:ok, _} = Index.shrink(%{}, "posts", "posts-small", context: context(port))
      assert Task.await(server).path == "/posts/_shrink/posts-small"
    end

    test "split/4 POSTs /{index}/_split/{target}" do
      {port, server} = start_server()

      assert {:ok, _} = Index.split(%{}, "posts", "posts-big", context: context(port))
      assert Task.await(server).path == "/posts/_split/posts-big"
    end

    test "each requires a target, naming it in the error" do
      for fun <- [&Index.clone/3, &Index.shrink/3, &Index.split/3] do
        assert {:error, %ArgumentError{} = error} = fun.(%{}, "posts", nil)
        assert Exception.message(error) =~ "target is required"
      end
    end
  end

  describe "rollover/3" do
    test "POSTs /{target}/_rollover" do
      {port, server} = start_server()

      assert {:ok, _} = Index.rollover(%{}, "logs", context: context(port))

      req = Task.await(server)
      assert req.method == "POST"
      assert req.path == "/logs/_rollover"
    end

    test "appends an explicit new index name" do
      {port, server} = start_server()

      assert {:ok, _} =
               Index.rollover(%{}, "logs", new_index: "logs-000002", context: context(port))

      assert Task.await(server).path == "/logs/_rollover/logs-000002"
    end

    test "rejects an empty new_index rather than silently dropping it" do
      assert {:error, %ArgumentError{} = error} = Index.rollover(%{}, "logs", new_index: "")
      assert Exception.message(error) =~ "new_index is required"
    end

    test "requires a target" do
      assert {:error, %ArgumentError{} = error} = Index.rollover(%{}, nil)
      assert Exception.message(error) =~ "target is required"
    end
  end

  describe "maintenance" do
    test "refresh/1 GETs /_refresh for all indices" do
      {port, server} = start_server()

      assert {:ok, _} = Index.refresh(context: context(port))

      req = Task.await(server)
      assert req.method == "GET"
      assert req.path == "/_refresh"
    end

    test "refresh/1 targets an index" do
      {port, server} = start_server()

      assert {:ok, _} = Index.refresh(index: "posts", context: context(port))
      assert Task.await(server).path == "/posts/_refresh"
    end

    test "flush/1 GETs /_flush" do
      {port, server} = start_server()

      assert {:ok, _} = Index.flush(index: "posts", context: context(port))

      req = Task.await(server)
      assert req.method == "GET"
      assert req.path == "/posts/_flush"
    end

    test "forcemerge/1 POSTs /_forcemerge" do
      {port, server} = start_server()

      assert {:ok, _} = Index.forcemerge(index: "posts", context: context(port))

      req = Task.await(server)
      assert req.method == "POST"
      assert req.path == "/posts/_forcemerge"
    end

    test "clear_cache/1 POSTs /_cache/clear" do
      {port, server} = start_server()

      assert {:ok, _} = Index.clear_cache(context: context(port))

      req = Task.await(server)
      assert req.method == "POST"
      assert req.path == "/_cache/clear"
    end
  end

  describe "monitoring" do
    test "stats/1 GETs /_stats" do
      {port, server} = start_server()

      assert {:ok, _} = Index.stats(context: context(port))

      req = Task.await(server)
      assert req.method == "GET"
      assert req.path == "/_stats"
    end

    test "stats/1 appends the metric after the index" do
      {port, server} = start_server()

      assert {:ok, _} = Index.stats(index: "posts", metric: "docs", context: context(port))
      assert Task.await(server).path == "/posts/_stats/docs"
    end

    test "stats/1 joins several metrics with commas" do
      {port, server} = start_server()

      assert {:ok, _} = Index.stats(metric: ["docs", "store"], context: context(port))
      assert Task.await(server).path == "/_stats/docs,store"
    end

    test "stats/1 rejects an empty metric" do
      assert {:error, %ArgumentError{} = error} = Index.stats(metric: "")
      assert Exception.message(error) =~ "metric is required"
    end

    test "segments/1 GETs /_segments" do
      {port, server} = start_server()

      assert {:ok, _} = Index.segments(index: "posts", context: context(port))
      assert Task.await(server).path == "/posts/_segments"
    end

    test "recovery/1 GETs /_recovery" do
      {port, server} = start_server()

      assert {:ok, _} = Index.recovery(context: context(port))
      assert Task.await(server).path == "/_recovery"
    end

    test "shard_stores/1 GETs /_shard_stores" do
      {port, server} = start_server()

      assert {:ok, _} = Index.shard_stores(index: "posts", context: context(port))
      assert Task.await(server).path == "/posts/_shard_stores"
    end
  end

  describe "resolve_index/2" do
    test "GETs /_resolve/index/{name}" do
      {port, server} = start_server()

      assert {:ok, _} = Index.resolve_index("logs-*", context: context(port))

      req = Task.await(server)
      assert req.method == "GET"
      assert req.path == "/_resolve/index/logs-*"
    end

    test "requires a name" do
      assert {:error, %ArgumentError{} = error} = Index.resolve_index(nil)
      assert Exception.message(error) =~ "name is required"
    end
  end

  defp context(port), do: HTTPStub.context(port)

  defp start_server(response \\ HTTPStub.ok_response()), do: HTTPStub.start_server(response)
end
