defmodule Norm do
  @moduledoc """
  Norm provides a set of functions for specifying data.
  """

  alias Norm.Spec

  defmodule MismatchError do
    defexception [:message]

    def exception(errors) do
      msg =
        errors
        |> Enum.join("\n")

      %__MODULE__{message: msg}
    end
  end

  defmodule GeneratorError do
    defexception [:message]

    def exception(predicate) do
      msg = "Unable to create a generator for: #{predicate}"
      %__MODULE__{message: msg}
    end
  end

  # iex> conform!(1, lit(1))
  # 1
  # iex> conform!("string", lit("string"))
  # "string"
  # iex> conform!(:atom, lit(:atom))
  # :atom
  # iex> conform(:atom, lit("string"))
  # {:error, ["val: :atom fails: \"string\""]}
  # iex> conform(1, string?())
  # {:error, ["val: 1 fails: string?()"]}
  # iex> conform!("foo", string?())
  # "foo"

  # iex> conform(:atom, sand(string?(), lit("foo")))
  # {:error, ["val: :atom fails: string?()", "val: :atom fails: \"foo\""]}
  # iex> conform!("foo", sand(string?(), lit("foo")))
  # "foo"
  # iex> conform!("foo", sor(string?(), integer?()))
  # "foo"
  # iex> conform!(1, sor(string?(), integer?()))
  # 1
  # iex> conform(:atom, sor(string?(), integer?()))
  # {:error, ["val: :atom fails: string?()", "val: :atom fails: integer?()"]}

  @doc ~S"""
  Verifies that the payload conforms to the specification

  iex> conform(42, is_integer())
  {:ok, 42}
  iex> conform(42, fn x -> x == 42 end)
  {:ok, 42}
  iex> conform(42, &(&1 >= 0))
  {:ok, 42}
  iex> conform(42, &(&1 >= 100))
  {:error, ["val: 42 fails: &(&1 >= 100)"]}
  iex> conform("foo", is_integer())
  {:error, ["val: \"foo\" fails: is_integer()"]}
  """
  defmacro conform(input, predicate) do
    spec = Spec.build(predicate)

    quote bind_quoted: [spec: spec, input: input] do
      Spec.conform(spec, input)
    end
  end

  @doc ~S"""
  Verifies that the payload conforms to the specification or raises a Mismatch
  error
  iex> conform!(42, is_integer())
  42
  iex> conform!("foo", is_integer())
  ** (Norm.MismatchError) val: "foo" fails: is_integer()
  """
  defmacro conform!(input, predicate) do
    spec = Spec.build(predicate)

    quote bind_quoted: [spec: spec, input: input] do
      case Spec.conform(spec, input) do
        {:ok, input} -> input
        {:error, errors} -> raise MismatchError, errors
      end
    end
  end

  @doc ~S"""
  Checks if the value conforms to the spec and returns a boolean.

  iex> valid?(42,  is_integer())
  true
  iex> valid?("foo",  is_integer())
  false
  """
  defmacro valid?(input, predicate) do
    spec = Spec.build(predicate)

    quote bind_quoted: [spec: spec, input: input] do
      case Spec.conform(spec, input) do
        {:ok, _}    -> true
        {:error, _} -> false
      end
    end
  end

  @doc ~S"""
  Creates a generator from a spec or predicate.

  iex> gen(is_integer()) |> Enum.take(3) |> Enum.all?(&is_integer/1)
  true
  iex> gen(is_binary()) |> Enum.take(3) |> Enum.all?(&is_binary/1)
  true
  iex> gen(&(&1 > 0))
  ** (Norm.GeneratorError) Unable to create a generator for: &(&1 > 0)
  """
  defmacro gen(predicate) do
    spec = Spec.build(predicate)

    quote bind_quoted: [spec: spec] do
      case Spec.gen(spec) do
        {:ok, generator} -> generator
        {:error, error} -> raise GeneratorError, error
      end
    end
  end






  # @doc ~S"""
  # Creates a spec for keyable things such as maps

  # iex> conform!(%{foo: "foo"}, keys(req: [foo: string?()]))
  # %{foo: "foo"}
  # iex> conform!(%{foo: "foo", bar: "bar"}, keys(req: [foo: string?()]))
  # %{foo: "foo"}
  # iex> conform!(%{"foo" => "foo", bar: "bar"}, keys(req: [{"foo", string?()}]))
  # %{"foo" => "foo"}
  # iex> conform!(%{foo: "foo"}, keys(req: [foo: string?()], opt: [bar: string?()]))
  # %{foo: "foo"}
  # iex> conform!(%{foo: "foo", bar: "bar"}, keys(req: [foo: string?()], opt: [bar: string?()]))
  # %{foo: "foo", bar: "bar"}
  # iex> conform(%{}, keys(req: [foo: string?()]))
  # {:error, ["in: :foo val: %{} fails: :required"]}
  # iex> conform(%{foo: 123, bar: "bar"}, keys(req: [foo: string?()]))
  # {:error, ["in: :foo val: 123 fails: string?()"]}
  # iex> conform(%{foo: 123, bar: 321}, keys(req: [foo: string?()], opt: [bar: string?()]))
  # {:error, ["in: :foo val: 123 fails: string?()", "in: :bar val: 321 fails: string?()"]}
  # iex> conform!(%{foo: "foo", bar: %{baz: "baz"}}, keys(req: [foo: string?(), bar: keys(req: [baz: lit("baz")])]))
  # %{foo: "foo", bar: %{baz: "baz"}}
  # iex> conform(%{foo: 123, bar: %{baz: 321}}, keys(req: [foo: string?()], opt: [bar: string?()]))
  # iex> conform(%{foo: 123, bar: %{baz: 321}}, keys(req: [foo: string?(), bar: keys(req: [baz: lit("baz")])]))
  # {:error, ["in: :foo val: 123 fails: string?()", "in: :bar/:baz val: 321 fails: \"baz\""]}
  # """
  # def keys(specs) do
  #   reqs = Keyword.get(specs, :req, [])
  #   opts = Keyword.get(specs, :opt, [])

  #   fn path, input ->
  #     req_keys = Enum.map(reqs, fn {key, _} -> key end)
  #     opt_keys = Enum.map(opts, fn {key, _} -> key end)

  #     req_errors =
  #       reqs
  #       |> Enum.map(fn {key, spec} ->
  #         # credo:disable-for-next-line /\.Nesting/
  #         if Map.has_key?(input, key) do
  #           {key, spec.(path ++ [key], input[key])}
  #         else
  #           {key, {:error, [error(path ++ [key], input, ":required")]}}
  #         end
  #       end)
  #       |> Enum.filter(fn {_, {result, _}} -> result == :error end)
  #       |> Enum.flat_map(fn {_, {_, errors}} -> errors end)

  #     opt_errors =
  #       opts
  #       |> Enum.map(fn {key, spec} ->
  #         # credo:disable-for-next-line /\.Nesting/
  #         if Map.has_key?(input, key) do
  #           {key, spec.(path ++ [key], input[key])}
  #         else
  #           {key, {:ok, nil}}
  #         end
  #       end)
  #       |> Enum.filter(fn {_, {result, _}} -> result == :error end)
  #       |> Enum.flat_map(fn {_, {_, errors}} -> errors end)

  #     errors = req_errors ++ opt_errors
  #     keys = req_keys ++ opt_keys

  #     if Enum.any?(errors) do
  #       {:error, errors}
  #     else
  #       {:ok, Map.take(input, keys)}
  #     end
  #   end
  # end

  # @doc ~S"""
  # Concatenates a sequence of predicates or patterns together. These predicates
  # must be tagged with an atom. The conformed data is returned as a
  # keyword list.

  # iex> conform!([31, "Chris"], cat(age: integer?(), name: string?()))
  # [age: 31, name: "Chris"]
  # iex> conform([true, "Chris"], cat(age: integer?(), name: string?()))
  # {:error, ["in: [0] at: :age val: true fails: integer?()"]}
  # iex> conform([31, :chris], cat(age: integer?(), name: string?()))
  # {:error, ["in: [1] at: :name val: :chris fails: string?()"]}
  # iex> conform([31], cat(age: integer?(), name: string?()))
  # {:error, ["in: [1] at: :name val: nil fails: Insufficient input"]}
  # """
  # def cat(opts) do
  #   fn path, input ->
  #     results =
  #       opts
  #       |> Enum.with_index
  #       |> Enum.map(fn {{tag, spec}, i} ->
  #         val = Enum.at(input, i)
  #         if val do
  #           {tag, spec.(path ++ [{:index, i}], val)}
  #         else
  #           {tag, {:error, [error(path ++ [{:index, i}], nil, "Insufficient input")]}}
  #         end
  #       end)

  #     errors =
  #       results
  #       |> Enum.filter(fn {_, {result, _}} -> result == :error end)
  #       |> Enum.map(fn {tag, {_, errors}} -> {tag, errors} end)
  #       |> Enum.flat_map(fn {tag, errors} -> Enum.map(errors, &(%{&1 | at: tag})) end)

  #     if Enum.any?(errors) do
  #       {:error, errors}
  #     else
  #       {:ok, Enum.map(results, fn {tag, {_, data}} -> {tag, data} end)}
  #     end
  #   end
  # end

  # @doc ~S"""
  # Choices between alternative predicates or patterns. The patterns must be tagged with an atom.
  # When conforming data to this specification the data is returned as a tuple with the tag.

  # iex> conform!(123, alt(num: integer?(), str: string?()))
  # {:num, 123}
  # iex> conform!("foo", alt(num: integer?(), str: string?()))
  # {:str, "foo"}
  # iex> conform(true, alt(num: integer?(), str: string?()))
  # {:error, ["in: :num val: true fails: integer?()", "in: :str val: true fails: string?()"]}
  # """
  # def alt(opts) do
  #   fn path, input ->
  #     results =
  #       opts
  #       |> Enum.map(fn {tag, spec} -> {tag, spec.(path ++ [tag], input)} end)

  #     good_result =
  #       results
  #       |> Enum.find(fn {_, {result, _}} -> result == :ok end)

  #     if good_result do
  #       {tag, {:ok, data}} = good_result
  #       {:ok, {tag, data}}
  #     else
  #       errors =
  #         results
  #         |> Enum.flat_map(fn {_, {_, errors}} -> errors end)

  #       {:error, errors}
  #     end
  #   end
  # end
end

