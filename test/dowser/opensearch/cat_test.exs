defmodule Dowser.Opensearch.CatTest do
  use ExUnit.Case, async: false

  alias Dowser.Opensearch.Cat
  alias Dowser.Opensearch.Error
  alias Dowser.Opensearch.HTTPStub

  @rows ~s([{"index":"posts","health":"green","docs.count":"42"}])
  @rows_response "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: #{byte_size(@rows)}\r\n\r\n" <>
                   @rows

  @help_text "=^.^=\n/_cat/allocation\n/_cat/shards\n/_cat/shards/{index}\n"
  @help_response "HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nContent-Length: #{byte_size(@help_text)}\r\n\r\n" <>
                   @help_text

  @server_error ~s({"message":"boom"})
  @server_error_response "HTTP/1.1 500 Internal Server Error\r\nContent-Type: application/json\r\nContent-Length: #{byte_size(@server_error)}\r\n\r\n" <>
                           @server_error

  describe "help/1" do
    test "GETs /_cat and parses the endpoint lines, dropping the banner" do
      {port, server} = start_server(@help_response)

      assert {:ok, endpoints} = Cat.help(context: context(port))
      assert endpoints == ["/_cat/allocation", "/_cat/shards", "/_cat/shards/{index}"]

      req = Task.await(server)
      assert req.method == "GET"
      assert req.path == "/_cat"
    end

    test "passes an error through instead of parsing it" do
      {port, server} = start_server(@server_error_response)

      assert {:error, %Error{status: 500}} = Cat.help(context: context(port))

      Task.await(server)
    end
  end

  describe "indices/1" do
    test "GETs /_cat/indices and decodes the rows as maps" do
      {port, server} = start_server(@rows_response)

      assert {:ok, [row]} = Cat.indices(context: context(port))
      assert row["index"] == "posts"
      assert row["docs.count"] == "42"

      req = Task.await(server)
      assert req.method == "GET"
      assert req.path == "/_cat/indices"
    end

    test "appends the index target" do
      {port, server} = start_server(@rows_response)

      assert {:ok, _} = Cat.indices(index: "posts*", context: context(port))
      assert Task.await(server).path == "/_cat/indices/posts*"
    end

    test "forwards the shared cat params" do
      {port, server} = start_server(@rows_response)

      assert {:ok, _} =
               Cat.indices(params: [v: true, h: "index,docs.count"], context: context(port))

      assert Task.await(server).path == "/_cat/indices?v=true&h=index%2Cdocs.count"
    end

    test "indices!/1 returns the rows directly" do
      {port, server} = start_server(@rows_response)

      assert [%{"index" => "posts"}] = Cat.indices!(context: context(port))

      Task.await(server)
    end
  end

  describe "endpoints with an optional path parameter" do
    test "each appends its own parameter to its own base path" do
      cases = [
        {&Cat.count/1, :index, "posts", "/_cat/count/posts"},
        {&Cat.aliases/1, :name, "blog", "/_cat/aliases/blog"},
        {&Cat.templates/1, :name, "logs", "/_cat/templates/logs"},
        {&Cat.fielddata/1, :fields, "title", "/_cat/fielddata/title"},
        {&Cat.shards/1, :index, "posts", "/_cat/shards/posts"},
        {&Cat.segments/1, :index, "posts", "/_cat/segments/posts"},
        {&Cat.recovery/1, :index, "posts", "/_cat/recovery/posts"},
        {&Cat.segment_replication/1, :index, "posts", "/_cat/segment_replication/posts"},
        {&Cat.allocation/1, :node_id, "node-1", "/_cat/allocation/node-1"},
        {&Cat.thread_pool/1, :thread_pool_patterns, "search", "/_cat/thread_pool/search"},
        {&Cat.snapshots/1, :repository, "backups", "/_cat/snapshots/backups"}
      ]

      for {fun, key, value, expected} <- cases do
        {port, server} = start_server(@rows_response)

        assert {:ok, _} = fun.([{key, value}, {:context, context(port)}])
        assert Task.await(server).path == expected
      end
    end

    test "each omits the parameter when it is absent" do
      cases = [
        {&Cat.count/1, "/_cat/count"},
        {&Cat.aliases/1, "/_cat/aliases"},
        {&Cat.templates/1, "/_cat/templates"},
        {&Cat.fielddata/1, "/_cat/fielddata"},
        {&Cat.shards/1, "/_cat/shards"},
        {&Cat.segments/1, "/_cat/segments"},
        {&Cat.recovery/1, "/_cat/recovery"},
        {&Cat.segment_replication/1, "/_cat/segment_replication"},
        {&Cat.allocation/1, "/_cat/allocation"},
        {&Cat.thread_pool/1, "/_cat/thread_pool"},
        {&Cat.snapshots/1, "/_cat/snapshots"}
      ]

      for {fun, expected} <- cases do
        {port, server} = start_server(@rows_response)

        assert {:ok, _} = fun.(context: context(port))
        assert Task.await(server).path == expected
      end
    end
  end

  describe "endpoints with no path parameter" do
    test "each GETs its fixed path" do
      cases = [
        {&Cat.nodes/1, "/_cat/nodes"},
        {&Cat.nodeattrs/1, "/_cat/nodeattrs"},
        {&Cat.cluster_manager/1, "/_cat/cluster_manager"},
        {&Cat.master/1, "/_cat/master"},
        {&Cat.health/1, "/_cat/health"},
        {&Cat.plugins/1, "/_cat/plugins"},
        {&Cat.tasks/1, "/_cat/tasks"},
        {&Cat.pending_tasks/1, "/_cat/pending_tasks"},
        {&Cat.repositories/1, "/_cat/repositories"},
        {&Cat.pit_segments/1, "/_cat/pit_segments"},
        {&Cat.all_pit_segments/1, "/_cat/pit_segments/_all"}
      ]

      for {fun, expected} <- cases do
        {port, server} = start_server(@rows_response)

        assert {:ok, _} = fun.(context: context(port))

        req = Task.await(server)
        assert req.method == "GET"
        assert req.path == expected
      end
    end
  end

  describe "aligned text" do
    test "resp_format: :raw leaves the body unparsed" do
      text = "health status index\ngreen  open   posts\n"

      response =
        "HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nContent-Length: #{byte_size(text)}\r\n\r\n" <>
          text

      {port, server} = start_server(response)

      assert {:ok, body} =
               Cat.indices(
                 params: [format: "text", v: true],
                 resp_format: :raw,
                 context: context(port)
               )

      assert body == text

      Task.await(server)
    end
  end

  describe "errors" do
    test "wraps a non-2xx response in a Dowser.Opensearch.Error" do
      {port, server} = start_server(@server_error_response)

      assert {:error, %Error{status: 500}} = Cat.nodes(context: context(port))

      Task.await(server)
    end

    test "the bang variant raises it" do
      {port, server} = start_server(@server_error_response)

      assert_raise Error, fn -> Cat.nodes!(context: context(port)) end

      Task.await(server)
    end
  end

  defp context(port), do: HTTPStub.context(port)

  defp start_server(response), do: HTTPStub.start_server(response)
end
