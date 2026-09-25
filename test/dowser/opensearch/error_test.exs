defmodule Dowser.Opensearch.ErrorTest do
  use ExUnit.Case, async: true

  alias Dowser.Opensearch.Error

  describe "new/2" do
    test "extracts :type and :reason from a standard error body" do
      body = %{"error" => %{"type" => "index_not_found_exception", "reason" => "no such index"}}

      assert %Error{
               status: 404,
               body: ^body,
               type: "index_not_found_exception",
               reason: "no such index"
             } =
               Error.new(404, body)
    end

    test "treats a plain string error as the reason, with no type" do
      body = %{"error" => "boom"}
      assert %Error{status: 500, type: nil, reason: "boom"} = Error.new(500, body)
    end

    test "extracts :type and :reason from an atom-keyed error body" do
      body = %{error: %{type: "index_not_found_exception", reason: "no such index"}}

      assert %Error{
               status: 404,
               body: ^body,
               type: "index_not_found_exception",
               reason: "no such index"
             } =
               Error.new(404, body)
    end

    test "treats a plain string error under an atom key as the reason" do
      body = %{error: "boom"}
      assert %Error{status: 500, type: nil, reason: "boom"} = Error.new(500, body)
    end

    test "leaves :type and :reason nil when the body has no error key" do
      body = %{"message" => "boom"}
      assert %Error{status: 500, type: nil, reason: nil} = Error.new(500, body)
    end

    test "leaves :type and :reason nil when the body is not a map" do
      assert %Error{status: 502, body: "<html>oops</html>", type: nil, reason: nil} =
               Error.new(502, "<html>oops</html>")

      assert %Error{status: 500, body: nil, type: nil, reason: nil} = Error.new(500, nil)
    end

    test "appends the first root_cause reason when it adds to the error reason" do
      body = %{
        "error" => %{
          "type" => "search_phase_execution_exception",
          "reason" => "all shards failed",
          "root_cause" => [
            %{"type" => "query_shard_exception", "reason" => "No mapping found for [date]"}
          ]
        }
      }

      assert %Error{
               type: "search_phase_execution_exception",
               reason: "all shards failed: No mapping found for [date]"
             } = Error.new(400, body)
    end

    test "appends the caused_by reason when there is no root_cause" do
      body = %{
        error: %{
          type: "illegal_argument_exception",
          reason: "failed to parse",
          caused_by: %{type: "number_format_exception", reason: ~s(For input string: "abc")}
        }
      }

      assert %Error{reason: ~s(failed to parse: For input string: "abc")} = Error.new(400, body)
    end

    test "does not repeat a nested reason the error reason already carries" do
      body = %{
        "error" => %{
          "type" => "index_not_found_exception",
          "reason" => "no such index [missing]",
          "root_cause" => [
            %{"type" => "index_not_found_exception", "reason" => "no such index [missing]"}
          ]
        }
      }

      assert %Error{reason: "no such index [missing]"} = Error.new(404, body)
    end

    test "accepts a nil status, for an error that is not a response of its own" do
      assert %Error{status: nil, type: "version_conflict_engine_exception"} =
               Error.new(nil, %{"error" => %{"type" => "version_conflict_engine_exception"}})
    end
  end

  describe "message/1" do
    test "includes both type and reason when present" do
      error = Error.new(404, %{"error" => %{"type" => "not_found", "reason" => "missing"}})

      assert Exception.message(error) ==
               "OpenSearch responded with HTTP 404: [not_found] missing"
    end

    test "includes only the reason when there is no type" do
      error = Error.new(500, %{"error" => "boom"})
      assert Exception.message(error) == "OpenSearch responded with HTTP 500: boom"
    end

    test "includes only the type when there is no reason" do
      error = Error.new(400, %{"error" => %{"type" => "bad_request"}})
      assert Exception.message(error) == "OpenSearch responded with HTTP 400: [bad_request]"
    end

    test "includes both type and reason from an atom-keyed body" do
      error = Error.new(404, %{error: %{type: "not_found", reason: "missing"}})

      assert Exception.message(error) ==
               "OpenSearch responded with HTTP 404: [not_found] missing"
    end

    test "reports a rejected execution from an atom-keyed 429 body" do
      body = %{
        error: %{
          type: "opensearch_rejected_execution_exception",
          reason:
            "rejected execution of coordinating operation [coordinating_and_primary_bytes=0]",
          root_cause: [
            %{
              type: "opensearch_rejected_execution_exception",
              reason:
                "rejected execution of coordinating operation [coordinating_and_primary_bytes=0]"
            }
          ]
        },
        status: 429
      }

      assert Exception.message(Error.new(429, body)) ==
               "OpenSearch responded with HTTP 429: [opensearch_rejected_execution_exception] " <>
                 "rejected execution of coordinating operation [coordinating_and_primary_bytes=0]"
    end

    test "falls back to just the status when neither is present" do
      error = Error.new(503, %{})
      assert Exception.message(error) == "OpenSearch responded with HTTP 503"
    end

    test "falls back to just the status when the body is not a map" do
      assert Exception.message(Error.new(502, "<html>oops</html>")) ==
               "OpenSearch responded with HTTP 502"
    end

    test "says an error was reported rather than responded when there is no status" do
      error = Error.new(nil, %{"error" => %{"type" => "mapper_parsing_exception"}})

      assert Exception.message(error) ==
               "OpenSearch reported an error: [mapper_parsing_exception]"
    end
  end
end
