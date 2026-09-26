defmodule Dowser.Opensearch.IndexTemplateTest do
  use ExUnit.Case, async: false

  alias Dowser.Opensearch.Error
  alias Dowser.Opensearch.HTTPStub
  alias Dowser.Opensearch.IndexTemplate

  @server_error ~s({"message":"boom"})
  @server_error_response "HTTP/1.1 500 Internal Server Error\r\nContent-Type: application/json\r\nContent-Length: #{byte_size(@server_error)}\r\n\r\n" <>
                           @server_error

  describe "index templates" do
    test "put_index_template/3 PUTs /_index_template/{name}" do
      {port, server} = start_server()

      template = %{"index_patterns" => ["logs-*"]}
      assert {:ok, _} = IndexTemplate.put_index_template(template, "logs", context: context(port))

      req = Task.await(server)
      assert req.method == "PUT"
      assert req.path == "/_index_template/logs"
      assert req.body == ~s({"index_patterns":["logs-*"]})
    end

    test "get_index_template/1 GETs all templates with no name" do
      {port, server} = start_server()

      assert {:ok, _} = IndexTemplate.get_index_template(context: context(port))

      req = Task.await(server)
      assert req.method == "GET"
      assert req.path == "/_index_template"
    end

    test "get_index_template/1 appends a name" do
      {port, server} = start_server()

      assert {:ok, _} = IndexTemplate.get_index_template(name: "logs*", context: context(port))
      assert Task.await(server).path == "/_index_template/logs*"
    end

    test "delete_index_template/2 DELETEs /_index_template/{name}" do
      {port, server} = start_server()

      assert {:ok, _} = IndexTemplate.delete_index_template("logs", context: context(port))

      req = Task.await(server)
      assert req.method == "DELETE"
      assert req.path == "/_index_template/logs"
    end

    test "index_template_exists/2 HEADs and maps 404 to false" do
      {port, server} = start_server(HTTPStub.head_response(404))

      assert IndexTemplate.index_template_exists("logs", context: context(port)) == {:ok, false}

      req = Task.await(server)
      assert req.method == "HEAD"
      assert req.path == "/_index_template/logs"
    end

    test "index_template_exists?/2 raises on a genuine error" do
      {port, server} = start_server(@server_error_response)

      assert_raise Error, fn ->
        IndexTemplate.index_template_exists?("logs", context: context(port))
      end

      Task.await(server)
    end

    test "each write requires a name" do
      assert {:error, %ArgumentError{} = error} = IndexTemplate.put_index_template(%{}, nil)
      assert Exception.message(error) =~ "name is required"

      assert {:error, %ArgumentError{}} = IndexTemplate.delete_index_template(nil)
      assert {:error, %ArgumentError{}} = IndexTemplate.index_template_exists(nil)
    end
  end

  describe "simulation" do
    test "simulate_index_template/3 POSTs /_index_template/_simulate_index/{name}" do
      {port, server} = start_server()

      assert {:ok, _} =
               IndexTemplate.simulate_index_template(%{}, "logs-2026", context: context(port))

      req = Task.await(server)
      assert req.method == "POST"
      assert req.path == "/_index_template/_simulate_index/logs-2026"
    end

    test "simulate_template/2 POSTs /_index_template/_simulate with no name" do
      {port, server} = start_server()

      body = %{"index_patterns" => ["logs-*"]}
      assert {:ok, _} = IndexTemplate.simulate_template(body, context: context(port))

      req = Task.await(server)
      assert req.method == "POST"
      assert req.path == "/_index_template/_simulate"
    end

    test "simulate_template/2 appends a stored template name" do
      {port, server} = start_server()

      assert {:ok, _} = IndexTemplate.simulate_template(%{}, name: "logs", context: context(port))
      assert Task.await(server).path == "/_index_template/_simulate/logs"
    end
  end

  describe "component templates" do
    test "put_component_template/3 PUTs /_component_template/{name}" do
      {port, server} = start_server()

      assert {:ok, _} =
               IndexTemplate.put_component_template(%{"template" => %{}}, "shards",
                 context: context(port)
               )

      req = Task.await(server)
      assert req.method == "PUT"
      assert req.path == "/_component_template/shards"
    end

    test "get_component_template/1 GETs all with no name" do
      {port, server} = start_server()

      assert {:ok, _} = IndexTemplate.get_component_template(context: context(port))
      assert Task.await(server).path == "/_component_template"
    end

    test "delete_component_template/2 DELETEs /_component_template/{name}" do
      {port, server} = start_server()

      assert {:ok, _} = IndexTemplate.delete_component_template("shards", context: context(port))

      req = Task.await(server)
      assert req.method == "DELETE"
      assert req.path == "/_component_template/shards"
    end

    test "component_template_exists/2 HEADs and maps 200 to true" do
      {port, server} = start_server(HTTPStub.head_response(200))

      assert IndexTemplate.component_template_exists("shards", context: context(port)) ==
               {:ok, true}

      assert Task.await(server).path == "/_component_template/shards"
    end
  end

  describe "legacy templates" do
    test "put_template/3 PUTs the legacy /_template/{name}" do
      {port, server} = start_server()

      assert {:ok, _} = IndexTemplate.put_template(%{}, "old-logs", context: context(port))

      req = Task.await(server)
      assert req.method == "PUT"
      assert req.path == "/_template/old-logs"
    end

    test "get_template/1 GETs /_template" do
      {port, server} = start_server()

      assert {:ok, _} = IndexTemplate.get_template(context: context(port))
      assert Task.await(server).path == "/_template"
    end

    test "get_template/1 joins several names with commas" do
      {port, server} = start_server()

      assert {:ok, _} = IndexTemplate.get_template(name: ["a", "b"], context: context(port))
      assert Task.await(server).path == "/_template/a,b"
    end

    test "delete_template/2 DELETEs /_template/{name}" do
      {port, server} = start_server()

      assert {:ok, _} = IndexTemplate.delete_template("old-logs", context: context(port))

      req = Task.await(server)
      assert req.method == "DELETE"
      assert req.path == "/_template/old-logs"
    end

    test "template_exists/2 HEADs /_template/{name}" do
      {port, server} = start_server(HTTPStub.head_response(200))

      assert IndexTemplate.template_exists("old-logs", context: context(port)) == {:ok, true}
      assert Task.await(server).path == "/_template/old-logs"
    end

    test "the legacy path is distinct from the composable one" do
      {port, server} = start_server()

      assert {:ok, _} = IndexTemplate.get_template(name: "logs", context: context(port))
      assert Task.await(server).path == "/_template/logs"

      {port, server} = start_server()

      assert {:ok, _} = IndexTemplate.get_index_template(name: "logs", context: context(port))
      assert Task.await(server).path == "/_index_template/logs"
    end
  end

  defp context(port), do: HTTPStub.context(port)

  defp start_server(response \\ HTTPStub.ok_response()), do: HTTPStub.start_server(response)
end
