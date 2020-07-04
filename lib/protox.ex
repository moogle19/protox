defmodule Protox do
  @moduledoc ~S'''
  Use this module to generate the Elixir modules from a set of protobuf definitions:

      defmodule Foo do
        use Protox, files: [
          "./defs/foo.proto",
          "./defs/bar.proto",
          "./defs/baz/fiz.proto",
        ]
      end

  It's also possible to directly give a schema:

      defmodule Bar do
        use Protox, schema: """
          syntax = "proto3";
          package fiz;

            message Baz {
            }

            message Foo {
              map<int32, Baz> b = 2;
            }
          """
      end

  The generated modules respect the package declaration. For instance, in the above example,
  both the `Fiz.Baz` and `Fiz.Foo` modules will be generated.

  See https://github.com/ahamez/protox/blob/master/README.md for detailed instructions.
  '''

  defmacro __using__(args) do
    {args, _} = Code.eval_quoted(args)

    namespace =
      case Keyword.get(args, :namespace) do
        nil -> nil
        n -> n
      end

    path =
      case Keyword.get(args, :path) do
        nil -> nil
        p -> Path.expand(p)
      end

    files =
      case Keyword.drop(args, [:namespace, :path]) do
        schema: <<text::binary>> ->
          filename = "#{__CALLER__.module}_#{:sha |> :crypto.hash(text) |> Base.encode16()}.proto"
          filepath = [Mix.Project.build_path(), filename] |> Path.join() |> Path.expand()
          File.write!(filepath, text)
          [filepath]

        files: files ->
          Enum.map(files, &Path.expand/1)
      end

    {:ok, file_descriptor_set} = Protox.Protoc.run(files, path)
    {enums, messages} = Protox.Parse.parse(file_descriptor_set, namespace)

    quote do
      unquote(make_external_resources(files))
      unquote(Protox.Define.define(enums, messages))
    end
  end

  def generate_code(files, include_path \\ nil) do
    path =
      case include_path do
        nil -> nil
        _ -> Path.expand(include_path)
      end

    {:ok, file_descriptor_set} =
      files
      |> Enum.map(&Path.expand/1)
      |> Protox.Protoc.run(path)

    {enums, messages} = Protox.Parse.parse(file_descriptor_set, nil)

    code = quote do: unquote(Protox.Define.define(enums, messages))

    code_str = Macro.to_string(code)

    ["#", " credo:disable-for-this-file\n", code_str]
  end

  defp make_external_resources(files) do
    Enum.map(files, fn file -> quote(do: @external_resource(unquote(file))) end)
  end
end
