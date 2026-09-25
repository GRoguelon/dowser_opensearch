defmodule Dowser.Opensearch.ReindexTest do
  use ExUnit.Case, async: false

  alias Dowser.Opensearch.Error
  alias Dowser.Opensearch.HTTPStub
  alias Dowser.Opensearch.Reindex

  @task ~s({"took":42,"timed_out":false,"total":100,"created":100,"failures":[]})
  @response "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: #{byte_size(@task)}\r\n\r\n" <>
              @task

  @server_error ~s({"message":"boom"})
  @server_error_response "HTTP/1.1 500 Internal Server Error\r\nContent-Type: application/json\r\nContent-Length: #{byte_size(@server_error)}\r\n\r\n" <>
                           @server_error

  describe "reindex/2" do
    test "POSTs the body to /_reindex and decodes the response" do
      {port, server} = start_server()

      body = %{"source" => %{"index" => "old"}, "dest" => %{"index" => "new"}}
      assert {:ok, decoded} = Reindex.reindex(body, context: context(port))
      assert decoded["created"] == 100

      req = Task.await(server)
      assert req.method == "POST"
      assert req.path == "/_reindex"
      assert req.body =~ ~s("source":{"index":"old"})
    end

    test "forwards wait_for_completion as a url param" do
      {port, server} = start_server()

      assert {:ok, _} =
               Reindex.reindex(%{}, params: [wait_for_completion: false], context: context(port))

      assert Task.await(server).path == "/_reindex?wait_for_completion=false"
    end

    test "wraps a non-2xx response in a Dowser.Opensearch.Error" do
      {port, server} = start_server(@server_error_response)

      assert {:error, %Error{status: 500}} = Reindex.reindex(%{}, context: context(port))

      Task.await(server)
    end

    test "is not retried after an ambiguous failure — it may have copied part of the work" do
      {port, requests} = counting_gateway()

      assert {:error, %Error{status: 504}} =
               Reindex.reindex(%{},
                 context: context(port),
                 retry: [base_delay_ms: 1, max_delay_ms: 1]
               )

      assert Agent.get(requests, & &1) == 1
    end
  end

  describe "reindex!/2" do
    test "returns the body directly" do
      {port, server} = start_server()

      assert %{"created" => 100} = Reindex.reindex!(%{}, context: context(port))

      Task.await(server)
    end

    test "raises the error exception" do
      {port, server} = start_server(@server_error_response)

      assert_raise Error, fn -> Reindex.reindex!(%{}, context: context(port)) end

      Task.await(server)
    end
  end

  describe "delete_by_query/3" do
    test "POSTs the query to /{index}/_delete_by_query" do
      {port, server} = start_server()

      assert {:ok, _} =
               Reindex.delete_by_query(%{"query" => %{"match_all" => %{}}}, "posts",
                 context: context(port)
               )

      req = Task.await(server)
      assert req.method == "POST"
      assert req.path == "/posts/_delete_by_query"
      assert req.body == ~s({"query":{"match_all":{}}})
    end

    test "joins several indices with commas" do
      {port, server} = start_server()

      assert {:ok, _} =
               Reindex.delete_by_query(%{}, ["posts", "comments"], context: context(port))

      assert Task.await(server).path == "/posts,comments/_delete_by_query"
    end

    test "requires an index" do
      assert {:error, %ArgumentError{} = error} = Reindex.delete_by_query(%{}, nil)
      assert Exception.message(error) =~ "requires an index"
    end

    test "delete_by_query!/3 raises when the index is missing" do
      assert_raise ArgumentError, ~r/requires an index/, fn ->
        Reindex.delete_by_query!(%{}, nil)
      end
    end
  end

  describe "update_by_query/3" do
    test "POSTs the body to /{index}/_update_by_query" do
      {port, server} = start_server()

      assert {:ok, _} = Reindex.update_by_query(%{}, "posts", context: context(port))

      req = Task.await(server)
      assert req.method == "POST"
      assert req.path == "/posts/_update_by_query"
      assert req.body == "{}"
    end

    test "requires an index" do
      assert {:error, %ArgumentError{}} = Reindex.update_by_query(%{}, nil)
    end
  end

  describe "rethrottling" do
    test "reindex_rethrottle/3 POSTs with requests_per_second" do
      {port, server} = start_server()

      assert {:ok, _} = Reindex.reindex_rethrottle("t:1", 10, context: context(port))

      req = Task.await(server)
      assert req.method == "POST"
      assert req.path == "/_reindex/t:1/_rethrottle?requests_per_second=10"
    end

    test "delete_by_query_rethrottle/3 POSTs with requests_per_second" do
      {port, server} = start_server()

      assert {:ok, _} = Reindex.delete_by_query_rethrottle("t:1", 10, context: context(port))
      assert Task.await(server).path == "/_delete_by_query/t:1/_rethrottle?requests_per_second=10"
    end

    test "update_by_query_rethrottle/3 accepts -1 to remove the throttle" do
      {port, server} = start_server()

      assert {:ok, _} = Reindex.update_by_query_rethrottle("t:1", -1, context: context(port))
      assert Task.await(server).path == "/_update_by_query/t:1/_rethrottle?requests_per_second=-1"
    end

    test "URL-encodes a task id" do
      {port, server} = start_server()

      assert {:ok, _} = Reindex.reindex_rethrottle("node a:1", 10, context: context(port))
      assert Task.await(server).path == "/_reindex/node%20a:1/_rethrottle?requests_per_second=10"
    end
  end

  defp context(port), do: HTTPStub.context(port)

  defp start_server(response \\ @response), do: HTTPStub.start_server(response)

  # A gateway that answers every request 504 — ambiguous: the request may have
  # reached OpenSearch and been applied.
  defp counting_gateway do
    {:ok, requests} = Agent.start_link(fn -> 0 end)

    port =
      HTTPStub.start_pool(fn _request ->
        Agent.update(requests, &(&1 + 1))
        "HTTP/1.1 504 Gateway Timeout\r\nContent-Length: 0\r\n\r\n"
      end)

    {port, requests}
  end
end
