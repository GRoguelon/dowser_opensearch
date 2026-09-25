defmodule Dowser.Opensearch.TargetTest do
  use ExUnit.Case, async: true

  alias Dowser.Opensearch.Target

  doctest Target

  describe "segment/1" do
    test "returns nil for an empty target" do
      assert Target.segment(nil) == nil
      assert Target.segment("") == nil
      assert Target.segment([]) == nil
    end

    test "encodes a single index given as a string" do
      assert Target.segment("posts") == "posts"
    end

    test "encodes a single index given as an atom" do
      assert Target.segment(:posts) == "posts"
    end

    test "joins several indices with a comma" do
      assert Target.segment(["posts", "comments"]) == "posts,comments"
      assert Target.segment([:posts, :comments]) == "posts,comments"
      assert Target.segment([:posts, "comments"]) == "posts,comments"
    end

    test "URL-encodes characters that are not valid in a path segment" do
      assert Target.segment("my comments") == "my%20comments"
      assert Target.segment(["posts", "my comments"]) == "posts,my%20comments"
    end

    test "leaves the wildcards and date-math characters OpenSearch expects" do
      assert Target.segment("logs-*") == "logs-*"
      assert Target.segment("-logs-2024") == "-logs-2024"
    end
  end
end
