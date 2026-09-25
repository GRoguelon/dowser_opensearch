defmodule Dowser.Opensearch.InfoTest do
  use ExUnit.Case, async: false

  alias Dowser.Opensearch.Error
  alias Dowser.Opensearch.HTTPStub
  alias Dowser.Opensearch.Info

  @info ~s({"name":"node-1","cluster_name":"opensearch-cluster","version":{"distribution":"opensearch","number":"2.13.0"},"tagline":"The OpenSearch Project: https://opensearch.org/"})
  @response "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: #{byte_size(@info)}\r\n\r\n" <>
              @info

  @server_error ~s({"message":"boom"})
  @server_error_response "HTTP/1.1 500 Internal Server Error\r\nContent-Type: application/json\r\nContent-Length: #{byte_size(@server_error)}\r\n\r\n" <>
                           @server_error

  describe "info/1" do
    test "GETs / and decodes the response" do
      {port, server} = start_server()

      assert {:ok, body} = Info.info(context: context(port))
      assert body["version"]["distribution"] == "opensearch"
      assert body["version"]["number"] == "2.13.0"

      req = Task.await(server)
      assert req.method == "GET"
      assert req.path == "/"
    end

    test "forwards url params" do
      {port, server} = start_server()

      assert {:ok, _} = Info.info(params: [human: true], context: context(port))
      assert Task.await(server).path == "/?human=true"
    end

    test "wraps a non-2xx response in a Dowser.Opensearch.Error" do
      {port, server} = start_server(@server_error_response)

      assert {:error, %Error{status: 500}} = Info.info(context: context(port))

      Task.await(server)
    end
  end

  describe "info!/1" do
    test "returns the body directly" do
      {port, server} = start_server()

      assert %{"name" => "node-1"} = Info.info!(context: context(port))

      Task.await(server)
    end

    test "raises the error exception" do
      {port, server} = start_server(@server_error_response)

      assert_raise Error, fn ->
        Info.info!(context: context(port))
      end

      Task.await(server)
    end
  end

  describe "ping/1" do
    test "HEADs / and returns true on a 2xx" do
      {port, server} = start_server(HTTPStub.head_response(200))

      assert Info.ping(context: context(port)) == {:ok, true}

      req = Task.await(server)
      assert req.method == "HEAD"
      assert req.path == "/"
    end

    test "returns false on a 404" do
      {port, server} = start_server(HTTPStub.head_response(404))

      assert Info.ping(context: context(port)) == {:ok, false}

      Task.await(server)
    end

    test "wraps any other status in a Dowser.Opensearch.Error" do
      {port, server} = start_server(@server_error_response)

      assert {:error, %Error{status: 500}} = Info.ping(context: context(port))

      Task.await(server)
    end
  end

  describe "ping?/1" do
    test "returns the boolean directly" do
      {port, server} = start_server(HTTPStub.head_response(200))

      assert Info.ping?(context: context(port)) == true

      Task.await(server)
    end

    test "returns false rather than raising for a 404" do
      {port, server} = start_server(HTTPStub.head_response(404))

      assert Info.ping?(context: context(port)) == false

      Task.await(server)
    end

    test "raises the error exception for a genuine failure" do
      {port, server} = start_server(@server_error_response)

      assert_raise Error, fn ->
        Info.ping?(context: context(port))
      end

      Task.await(server)
    end
  end

  defp context(port), do: HTTPStub.context(port)

  defp start_server(response \\ @response), do: HTTPStub.start_server(response)
end
