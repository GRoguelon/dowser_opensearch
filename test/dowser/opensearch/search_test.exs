defmodule Dowser.Opensearch.SearchTest do
  use ExUnit.Case, async: false

  alias Dowser.Opensearch.Error
  alias Dowser.Opensearch.HTTPStub
  alias Dowser.Opensearch.Search

  @hits ~s({"hits":{"total":{"value":1},"hits":[{"_id":"1"}]}})
  @response "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: #{byte_size(@hits)}\r\n\r\n" <>
              @hits

  @not_found ~s({"error":{"type":"index_not_found_exception","reason":"no such index [missing]"},"status":404})
  @not_found_response "HTTP/1.1 404 Not Found\r\nContent-Type: application/json\r\nContent-Length: #{byte_size(@not_found)}\r\n\r\n" <>
                        @not_found

  @server_error ~s({"message":"boom"})
  @server_error_response "HTTP/1.1 500 Internal Server Error\r\nContent-Type: application/json\r\nContent-Length: #{byte_size(@server_error)}\r\n\r\n" <>
                           @server_error

  describe "search/2" do
    test "POSTs the query to /_search and decodes the response" do
      {port, server} = start_server()

      assert {:ok, body} =
               Search.search(%{"query" => %{"match_all" => %{}}}, context: context(port))

      assert body["hits"]["total"]["value"] == 1

      req = Task.await(server)
      assert req.method == "POST"
      assert req.path == "/_search"
      assert req.body == ~s({"query":{"match_all":{}}})
      assert req.headers["content-type"] == "application/json"
    end

    test "targets a single index" do
      {port, server} = start_server()

      assert {:ok, _} = Search.search(%{}, index: "posts", context: context(port))
      assert Task.await(server).path == "/posts/_search"
    end

    test "joins several indices with commas" do
      {port, server} = start_server()

      assert {:ok, _} = Search.search(%{}, index: ["posts", "comments"], context: context(port))
      assert Task.await(server).path == "/posts,comments/_search"
    end

    test "forwards url params" do
      {port, server} = start_server()

      assert {:ok, _} =
               Search.search(%{}, index: "posts", params: [routing: "u1"], context: context(port))

      assert Task.await(server).path == "/posts/_search?routing=u1"
    end

    test "wraps a 404 in a Dowser.Opensearch.Error with type and reason" do
      {port, server} = start_server(@not_found_response)

      assert {:error, %Error{status: 404, type: "index_not_found_exception", reason: reason}} =
               Search.search(%{}, index: "missing", context: context(port))

      assert reason =~ "no such index"

      Task.await(server)
    end

    test "wraps a 500 with no error object" do
      {port, server} = start_server(@server_error_response)

      assert {:error, %Error{status: 500, type: nil, reason: nil}} =
               Search.search(%{}, context: context(port))

      Task.await(server)
    end
  end

  describe "retries" do
    test "a search is retried after an ambiguous failure, POST or not" do
      {:ok, requests} = Agent.start_link(fn -> 0 end)

      port =
        HTTPStub.start_pool(fn _request ->
          Agent.update(requests, &(&1 + 1))
          "HTTP/1.1 504 Gateway Timeout\r\nContent-Length: 0\r\n\r\n"
        end)

      assert {:error, %Error{status: 504}} =
               Search.search(%{"query" => %{"match_all" => %{}}},
                 context: context(port),
                 retry: [base_delay_ms: 1, max_delay_ms: 1]
               )

      # A search writes nothing, so re-sending it after a 504 is free.
      assert Agent.get(requests, & &1) == 3
    end
  end

  describe "search!/2" do
    test "returns the decoded body directly" do
      {port, server} = start_server()

      assert %{"hits" => %{"total" => %{"value" => 1}}} =
               Search.search!(%{}, context: context(port))

      Task.await(server)
    end

    test "raises the Dowser.Opensearch.Error on a non-2xx response" do
      {port, server} = start_server(@not_found_response)

      assert_raise Error, ~r/HTTP 404.*no such index/, fn ->
        Search.search!(%{}, index: "missing", context: context(port))
      end

      Task.await(server)
    end
  end

  describe "msearch/2" do
    test "POSTs NDJSON to /_msearch" do
      {port, server} = start_server()

      searches = [%{}, %{"query" => %{"match_all" => %{}}}]
      assert {:ok, _} = Search.msearch(searches, context: context(port))

      req = Task.await(server)
      assert req.method == "POST"
      assert req.path == "/_msearch"
      assert req.headers["content-type"] == "application/x-ndjson"
      assert req.body == ~s({}\n{"query":{"match_all":{}}}\n)
    end

    test "targets an index" do
      {port, server} = start_server()

      assert {:ok, _} = Search.msearch([%{}, %{}], index: "posts", context: context(port))
      assert Task.await(server).path == "/posts/_msearch"
    end
  end

  describe "count/2" do
    test "POSTs the query to /_count" do
      {port, server} = start_server()

      assert {:ok, _} = Search.count(%{"query" => %{"match_all" => %{}}}, context: context(port))

      req = Task.await(server)
      assert req.method == "POST"
      assert req.path == "/_count"
    end

    test "targets an index" do
      {port, server} = start_server()

      assert {:ok, _} = Search.count(%{}, index: "posts", context: context(port))
      assert Task.await(server).path == "/posts/_count"
    end
  end

  describe "explain/4" do
    test "POSTs to /{index}/_explain/{id}" do
      {port, server} = start_server()

      assert {:ok, _} = Search.explain(%{}, "posts", "1", context: context(port))

      req = Task.await(server)
      assert req.method == "POST"
      assert req.path == "/posts/_explain/1"
    end

    test "URL-encodes the id" do
      {port, server} = start_server()

      assert {:ok, _} = Search.explain(%{}, "posts", "a b", context: context(port))
      assert Task.await(server).path == "/posts/_explain/a%20b"
    end

    test "requires an index" do
      assert {:error, %ArgumentError{} = error} = Search.explain(%{}, nil, "1")
      assert Exception.message(error) =~ "requires an index"
    end
  end

  describe "field_caps/2" do
    test "POSTs to /_field_caps" do
      {port, server} = start_server()

      assert {:ok, _} = Search.field_caps(%{fields: ["title"]}, context: context(port))

      req = Task.await(server)
      assert req.method == "POST"
      assert req.path == "/_field_caps"
    end

    test "targets an index" do
      {port, server} = start_server()

      assert {:ok, _} = Search.field_caps(%{}, index: "posts", context: context(port))
      assert Task.await(server).path == "/posts/_field_caps"
    end
  end

  describe "search_shards/1" do
    test "GETs /_search_shards" do
      {port, server} = start_server()

      assert {:ok, _} = Search.search_shards(context: context(port))

      req = Task.await(server)
      assert req.method == "GET"
      assert req.path == "/_search_shards"
    end

    test "targets an index" do
      {port, server} = start_server()

      assert {:ok, _} = Search.search_shards(index: "posts", context: context(port))
      assert Task.await(server).path == "/posts/_search_shards"
    end
  end

  describe "validate_query/2" do
    test "POSTs the query to /_validate/query" do
      {port, server} = start_server()

      assert {:ok, _} =
               Search.validate_query(%{"query" => %{"match_all" => %{}}}, context: context(port))

      req = Task.await(server)
      assert req.method == "POST"
      assert req.path == "/_validate/query"
      assert req.body == ~s({"query":{"match_all":{}}})
    end

    test "targets an index and forwards explain" do
      {port, server} = start_server()

      assert {:ok, _} =
               Search.validate_query(%{},
                 index: "posts",
                 params: [explain: true],
                 context: context(port)
               )

      assert Task.await(server).path == "/posts/_validate/query?explain=true"
    end
  end

  describe "search_template/2" do
    test "POSTs to /_search/template" do
      {port, server} = start_server()

      assert {:ok, _} = Search.search_template(%{id: "t1"}, context: context(port))

      req = Task.await(server)
      assert req.method == "POST"
      assert req.path == "/_search/template"
    end

    test "targets an index" do
      {port, server} = start_server()

      assert {:ok, _} = Search.search_template(%{}, index: "posts", context: context(port))
      assert Task.await(server).path == "/posts/_search/template"
    end
  end

  describe "msearch_template/2" do
    test "POSTs NDJSON to /_msearch/template" do
      {port, server} = start_server()

      assert {:ok, _} = Search.msearch_template([%{}, %{id: "t1"}], context: context(port))

      req = Task.await(server)
      assert req.path == "/_msearch/template"
      assert req.headers["content-type"] == "application/x-ndjson"
    end
  end

  describe "render_search_template/2" do
    test "POSTs to /_render/template with no id" do
      {port, server} = start_server()

      assert {:ok, _} = Search.render_search_template(%{source: "{}"}, context: context(port))

      req = Task.await(server)
      assert req.method == "POST"
      assert req.path == "/_render/template"
    end

    test "appends the stored template id when given" do
      {port, server} = start_server()

      assert {:ok, _} =
               Search.render_search_template(%{params: %{}}, id: "t1", context: context(port))

      assert Task.await(server).path == "/_render/template/t1"
    end
  end

  describe "scroll" do
    test "scroll/2 POSTs the scroll id in the body" do
      {port, server} = start_server()

      assert {:ok, _} = Search.scroll("c2Nhbg==", scroll: "1m", context: context(port))

      req = Task.await(server)
      assert req.method == "POST"
      assert req.path == "/_search/scroll"
      assert req.body =~ ~s("scroll_id":"c2Nhbg==")
      assert req.body =~ ~s("scroll":"1m")
    end

    test "clear_scroll/2 DELETEs with the scroll ids in the body" do
      {port, server} = start_server()

      assert {:ok, _} = Search.clear_scroll(["a", "b"], context: context(port))

      req = Task.await(server)
      assert req.method == "DELETE"
      assert req.path == "/_search/scroll"
      assert req.body == ~s({"scroll_id":["a","b"]})
    end
  end

  describe "point in time" do
    test "create_pit/3 POSTs /{index}/_search/point_in_time with keep_alive" do
      {port, server} = start_server()

      assert {:ok, _} = Search.create_pit("posts", "1m", context: context(port))

      req = Task.await(server)
      assert req.method == "POST"
      assert req.path == "/posts/_search/point_in_time?keep_alive=1m"
    end

    test "create_pit/3 requires an index" do
      assert {:error, %ArgumentError{} = error} = Search.create_pit(nil, "1m")
      assert Exception.message(error) =~ "requires an index"
    end

    test "create_pit!/3 raises when the index is missing" do
      assert_raise ArgumentError, ~r/requires an index/, fn ->
        Search.create_pit!(nil, "1m")
      end
    end

    test "delete_pit/2 DELETEs with the ids as an array, wrapping a single one" do
      {port, server} = start_server()

      assert {:ok, _} = Search.delete_pit("pit-id", context: context(port))

      req = Task.await(server)
      assert req.method == "DELETE"
      assert req.path == "/_search/point_in_time"
      # OpenSearch requires pit_id to be an array, even for one id.
      assert req.body == ~s({"pit_id":["pit-id"]})
    end

    test "delete_pit/2 passes a list through unchanged" do
      {port, server} = start_server()

      assert {:ok, _} = Search.delete_pit(["a", "b"], context: context(port))
      assert Task.await(server).body == ~s({"pit_id":["a","b"]})
    end

    test "delete_all_pits/1 DELETEs the _all path" do
      {port, server} = start_server()

      assert {:ok, _} = Search.delete_all_pits(context: context(port))

      req = Task.await(server)
      assert req.method == "DELETE"
      assert req.path == "/_search/point_in_time/_all"
    end

    test "get_all_pits/1 GETs the _all path" do
      {port, server} = start_server()

      assert {:ok, _} = Search.get_all_pits(context: context(port))

      req = Task.await(server)
      assert req.method == "GET"
      assert req.path == "/_search/point_in_time/_all"
    end
  end

  describe "type casting via Codec" do
    test "each hit's _source is cast against its own index mapping, at any nesting depth" do
      mapping = %{
        "properties" => %{
          "published_at" => %{"type" => "date", "format" => "strict_date_optional_time"}
        }
      }

      HTTPStub.start_mapping_cacher!(mapping)

      hits =
        ~s({"took":1,"hits":{"total":{"value":1},"hits":[{"_index":"posts","_id":"1","_source":{"published_at":"2026-08-11T00:00:00.000Z"}}]}})

      response =
        "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: #{byte_size(hits)}\r\n\r\n" <>
          hits

      {port, server} = start_server(response)

      assert {:ok, body} = Search.search(%{}, context: HTTPStub.context_with_casting(port))

      [hit] = body["hits"]["hits"]
      assert hit["_source"]["published_at"] == ~U[2026-08-11 00:00:00.000Z]

      Task.await(server)
    end
  end

  defp context(port), do: HTTPStub.context(port)

  defp start_server(response \\ @response), do: HTTPStub.start_server(response)
end
