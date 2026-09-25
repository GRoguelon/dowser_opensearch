defmodule Dowser.Opensearch.HelpersTest do
  use ExUnit.Case, async: true

  alias Dowser.Client.Response
  alias Dowser.Opensearch.Error
  alias Dowser.Opensearch.Helpers
  alias Dowser.Opensearch.MappingError

  describe "parse_result/1" do
    test "returns the body for any 2xx status" do
      for status <- [200, 201, 204, 299] do
        assert Helpers.parse_result({:ok, %Response{status: status, body: %{"ok" => true}}}) ==
                 {:ok, %{"ok" => true}}
      end
    end

    test "returns an Error for a non-2xx status" do
      body = %{"error" => %{"type" => "index_not_found_exception", "reason" => "no such index"}}

      assert {:error, %Error{status: 404, type: "index_not_found_exception"}} =
               Helpers.parse_result({:ok, %Response{status: 404, body: body}})
    end

    test "unwraps a MappingError from a decode failure" do
      error = %MappingError{index: "posts", reason: :timeout}
      client_error = %Dowser.Client.Error{reason: {:decode_failed, error}}

      assert Helpers.parse_result({:error, client_error}) == {:error, error}
    end

    test "unwraps a MappingError from an encode failure" do
      error = %MappingError{index: "posts", reason: :timeout}
      client_error = %Dowser.Client.Error{reason: {:encode_failed, error}}

      assert Helpers.parse_result({:error, client_error}) == {:error, error}
    end

    test "passes any other client error through untouched" do
      client_error = %Dowser.Client.Error{reason: {:decode_failed, :invalid_json}}

      assert Helpers.parse_result({:error, client_error}) == {:error, client_error}
    end

    test "passes a transport error through untouched" do
      error = %RuntimeError{message: "econnrefused"}

      assert Helpers.parse_result({:error, error}) == {:error, error}
    end
  end

  describe "parse_exists/1" do
    test "returns true for a 2xx status" do
      assert Helpers.parse_exists({:ok, %Response{status: 200, body: nil}}) == {:ok, true}
    end

    test "returns false for a 404" do
      assert Helpers.parse_exists({:ok, %Response{status: 404, body: nil}}) == {:ok, false}
    end

    test "returns an Error for any other status" do
      assert {:error, %Error{status: 503}} =
               Helpers.parse_exists({:ok, %Response{status: 503, body: %{}}})
    end

    test "passes a transport error through untouched" do
      error = %RuntimeError{message: "econnrefused"}

      assert Helpers.parse_exists({:error, error}) == {:error, error}
    end
  end

  describe "path/2" do
    test "prefixes the index when there is one" do
      assert Helpers.path("posts", "/_search") == "/posts/_search"
      assert Helpers.path(["posts", "comments"], "/_search") == "/posts,comments/_search"
    end

    test "returns the bare suffix when the index is empty" do
      assert Helpers.path(nil, "/_search") == "/_search"
      assert Helpers.path([], "/_search") == "/_search"
    end
  end

  describe "suffix_path/3" do
    test "appends the target after the base" do
      assert Helpers.suffix_path("/_cat/indices", "posts") == "/_cat/indices/posts"
    end

    test "inserts the infix between the base and the target" do
      assert Helpers.suffix_path("/_cluster/state", "posts", "/_all") ==
               "/_cluster/state/_all/posts"
    end

    test "returns the bare base when the target is empty" do
      assert Helpers.suffix_path("/_cat/indices", nil) == "/_cat/indices"
      assert Helpers.suffix_path("/_cluster/state", nil, "/_all") == "/_cluster/state"
    end
  end

  describe "required_path/2" do
    test "builds the path when the index is present" do
      assert Helpers.required_path("posts", "/_doc") == {:ok, "/posts/_doc"}
    end

    test "returns an ArgumentError naming the value when the index is empty" do
      assert {:error, %ArgumentError{message: message}} = Helpers.required_path(nil, "/_doc")
      assert message == "this endpoint requires an index, got: nil"
    end
  end

  describe "required_segment/2" do
    test "encodes the value when it is present" do
      assert Helpers.required_segment("my policy", "policy") == {:ok, "my%20policy"}
    end

    test "returns an ArgumentError naming the label when the value is empty" do
      assert {:error, %ArgumentError{message: message}} = Helpers.required_segment("", "policy")
      assert message == ~s(policy is required, got: "")
    end
  end

  describe "put_default_format/3" do
    test "applies the default when neither key nor :format is set" do
      assert Helpers.put_default_format([], :req_format, :ndjson) == [req_format: :ndjson]
    end

    test "leaves a value the caller already set for that key" do
      assert Helpers.put_default_format([req_format: :json], :req_format, :ndjson) ==
               [req_format: :json]
    end

    test "applies nothing when the caller set the mutually exclusive :format" do
      assert Helpers.put_default_format([format: :json], :req_format, :ndjson) == [format: :json]
    end
  end

  describe "put_idempotent/2" do
    test "marks the request when no :retry option is set" do
      assert Helpers.put_idempotent([], true) == [retry: [idempotent: true]]
      assert Helpers.put_idempotent([], false) == [retry: [idempotent: false]]
    end

    test "preserves other retry options" do
      assert Helpers.put_idempotent([retry: [max_attempts: 5]], true) ==
               [retry: [idempotent: true, max_attempts: 5]]
    end

    test "leaves an :idempotent the caller set" do
      assert Helpers.put_idempotent([retry: [idempotent: false]], true) ==
               [retry: [idempotent: false]]
    end

    test "leaves retry: false alone rather than turning retries back on" do
      assert Helpers.put_idempotent([retry: false], true) == [retry: false]
    end
  end

  describe "put_param/3" do
    test "adds the parameter when there are none" do
      assert Helpers.put_param([], :scroll, "1m") == [params: [scroll: "1m"]]
    end

    test "appends to the parameters the caller already set" do
      assert Helpers.put_param([params: [size: 10]], :scroll, "1m") ==
               [params: [size: 10, scroll: "1m"]]
    end

    test "accepts a map of parameters" do
      assert [params: params] = Helpers.put_param([params: %{size: 10}], :scroll, "1m")
      assert Enum.sort(params) == [scroll: "1m", size: 10]
    end
  end
end
