defmodule Saxy do
  @moduledoc ~S"""
  Saxy is an XML SAX parser and encoder.

  Saxy provides functions to parse XML file in both binary and streaming way in compliant
  with [Extensible Markup Language (XML) 1.0 (Fifth Edition)](https://www.w3.org/TR/xml/).

  Saxy also offers DSL and API to build, compose and encode XML document.
  See "Encoder" section below for more information.

  ## Parser

  Saxy parser supports two modes of parsing: SAX and simple form.

  ### SAX mode (Simple API for XML)

  SAX is an event driven algorithm for parsing XML documents. A SAX parser takes XML document as the input
  and emits events out to a pre-configured event handler during parsing.

  There are 5 types of SAX events supported by Saxy:

  * `:start_document` - after prolog is parsed.
  * `:start_element` - when open tag is parsed.
  * `:characters` - when a chunk of `CharData` is parsed.
  * `:end_element` - when end tag is parsed.
  * `:end_document` - when the root element is closed.

  See `Saxy.Handler` for more information.

  ### Simple form mode

  Saxy supports parsing XML documents into a simple format. See `Saxy.SimpleForm` for more details.

  ### Encoding

  Saxy **only** supports UTF-8 encoding. It also respects the encoding set in XML document prolog, which means
  that if the declared encoding is not UTF-8, the parser stops. Anyway, when there is no encoding declared,
  Saxy defaults the encoding to UTF-8.

  ### Reference expansion

  Saxy supports expanding character references and XML 1.0 predefined entity references, for example `&#65;`
  is expanded to `"A"`, `&#x26;` to `"&"`, and `&amp;` to `"&"`.

  Saxy does not expand external entity references, but provides an option to specify how they should be handled.
  See more in "Shared options" section.

  ### Creation of atoms

  Saxy does not create atoms during the parsing process.

  ### DTD and XSD

  Saxy does not support DTD (Doctype Definition) and XSD schemas.

  ### Shared options

  * `:expand_entity` - specifies how external entity references should be handled. Three supported strategies respectively are:
    * `:keep` - keep the original binary, for example `Orange &reg;` will be expanded to `"Orange &reg;"`, this is the default strategy.
    * `:skip` - skip the original binary, for example `Orange &reg;` will be expanded to `"Orange "`.
    * `{mod, fun, args}` - take the applied result of the specified MFA.

  ## Encoder

  Saxy offers two APIs to build simple form and encode XML document.

  Use `Saxy.XML` to build and compose XML simple form, then `Saxy.encode!/2`
  to encode the built element into XML binary.

      iex> import Saxy.XML
      iex> element = element("person", [gender: "female"], "Alice")
      {"person", [{"gender", "female"}], [{:characters, "Alice"}]}
      iex> Saxy.encode!(element, [])
      "<?xml version=\"1.0\"?><person gender=\"female\">Alice</person>"

  See `Saxy.XML` for more XML building APIs.

  Saxy also provides `Saxy.Builder` protocol to help composing structs into simple form.

      defmodule Person do
        @derive {Saxy.Builder, name: "person", attributes: [:gender], children: [:name]}

        defstruct [:gender, :name]
      end

      iex> jack = %Person{gender: :male, name: "Jack"}
      iex> john = %Person{gender: :male, name: "John"}
      iex> import Saxy.XML
      iex> root = element("people", [], [jack, john])
      iex> Saxy.encode!(root, [])
      "<?xml version=\"1.0\"?><people><person gender=\"male\">Jack</person><person gender=\"male\">John</person></people>"

  """

  alias Saxy.{
    Encoder,
    Parser,
    State
  }

  @doc ~S"""
  Parses XML binary data.

  This function takes XML binary, SAX event handler (see more at `Saxy.Handler`) and an initial state as the input, it returns
  `{:ok, state}` if parsing is successful, otherwise `{:error, exception}`, where `exception` is a
  `Saxy.ParseError` struct which can be converted into readable message with `Exception.message/1`.

  The third argument `state` can be used to keep track of data and parsing progress when parsing is happening, which will be
  returned when parsing finishes.

  ### Options

  See the “Shared options” section at the module documentation.

  ## Examples

      defmodule MyTestHandler do
        @behaviour Saxy.Handler

        def handle_event(:start_document, prolog, state) do
          {:ok, [{:start_document, prolog} | state]}
        end

        def handle_event(:end_document, _data, state) do
          {:ok, [{:end_document} | state]}
        end

        def handle_event(:start_element, {name, attributes}, state) do
          {:ok, [{:start_element, name, attributes} | state]}
        end

        def handle_event(:end_element, name, state) do
          {:ok, [{:end_element, name} | state]}
        end

        def handle_event(:characters, chars, state) do
          {:ok, [{:chacters, chars} | state]}
        end
      end

      iex> xml = "<?xml version='1.0' ?><foo bar='value'></foo>"
      iex> Saxy.parse_string(xml, MyTestHandler, [])
      {:ok,
       [{:end_document},
        {:end_element, "foo"},
        {:start_element, "foo", [{"bar", "value"}]},
        {:start_document, [version: "1.0"]}]}
  """

  @spec parse_string(
          data :: binary,
          handler :: module() | function(),
          initial_state :: term(),
          options :: Keyword.t()
        ) :: {:ok, state :: term()} | {:error, exception :: Saxy.ParseError.t()}
  def parse_string(data, handler, initial_state, options \\ [])
      when is_binary(data) and is_atom(handler) do
    expand_entity = Keyword.get(options, :expand_entity, :keep)

    state = %State{
      prolog: nil,
      handler: handler,
      user_state: initial_state,
      expand_entity: expand_entity
    }

    case Parser.Prolog.parse(data, false, data, 0, state) do
      {:ok, state} ->
        {:ok, state.user_state}

      {:error, _reason} = error ->
        error
    end
  end

  @doc ~S"""
  Parses XML stream data.

  This function takes a stream, SAX event handler (see more at `Saxy.Handler`) and an initial state as the input, it returns
  `{:ok, state}` if parsing is successful, otherwise `{:error, exception}`, where `exception` is a
  `Saxy.ParseError` struct which can be converted into readable message with `Exception.message/1`.

  ## Examples

      defmodule MyTestHandler do
        @behaviour Saxy.Handler

        def handle_event(:start_document, prolog, state) do
          {:ok, [{:start_document, prolog} | state]}
        end

        def handle_event(:end_document, _data, state) do
          {:ok, [{:end_document} | state]}
        end

        def handle_event(:start_element, {name, attributes}, state) do
          {:ok, [{:start_element, name, attributes} | state]}
        end

        def handle_event(:end_element, {name}, state) do
          {:ok, [{:end_element, name} | state]}
        end

        def handle_event(:characters, chars, state) do
          {:ok, [{:chacters, chars} | state]}
        end
      end

      iex> stream = File.stream!("./test/support/fixture/foo.xml")
      iex> Saxy.parse_stream(stream, MyTestHandler, [])
      {:ok,
       [{:end_document},
        {:end_element, "foo"},
        {:start_element, "foo", [{"bar", "value"}]},
        {:start_document, [version: "1.0"]}]}

  ## Memory usage

  `Saxy.parse_stream/3` takes a `File.Stream` or `Stream` as the input, so the amount of bytes to buffer in each
  chunk can be controlled by `File.stream!/3` API.

  During parsing, the actual memory used by Saxy might be higher than the number configured for each chunk, since
  Saxy holds in memory some parsed parts of the original binary to leverage Erlang sub-binary extracting. Anyway,
  Saxy tries to free those up when it makes sense.

  ### Options

  See the “Shared options” section at the module documentation.

  """

  @spec parse_stream(
          stream :: Enumerable.t(),
          handler :: module() | function(),
          initial_state :: term(),
          options :: Keyword.t()
        ) :: {:ok, state :: term()} | {:error, exception :: Saxy.ParseError.t()}

  def parse_stream(stream, handler, initial_state, options \\ []) do
    expand_entity = Keyword.get(options, :expand_entity, :keep)

    state = %State{
      prolog: nil,
      handler: handler,
      user_state: initial_state,
      expand_entity: expand_entity
    }

    init = Parser.Prolog.parse(<<>>, true, <<>>, 0, state)

    stream
    |> Enum.reduce_while(init, &stream_reducer/2)
    |> case do
      {:halted, context_fun} ->
        case context_fun.(<<>>, false) do
          {:ok, state} -> {:ok, state.user_state}
          {:error, reason} -> {:error, reason}
        end

      {:ok, state} ->
        {:ok, state.user_state}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp stream_reducer(next_bytes, {:halted, context_fun}) do
    {:cont, context_fun.(next_bytes, true)}
  end

  defp stream_reducer(_next_bytes, {:error, _reason} = error) do
    {:halt, error}
  end

  defp stream_reducer(_next_bytes, {:ok, state}) do
    {:halt, {:ok, state}}
  end

  @doc """
  Encodes a simple form XML element into string.

  This function encodes an element in simple form format and a prolog to an XML document.

  ## Examples

      iex> import Saxy.XML
      iex> root = element(:foo, [{"foo", "bar"}], "bar")
      iex> prolog = [version: "1.0"]
      iex> Saxy.encode!(root, prolog)
      "<?xml version=\\"1.0\\"?><foo foo=\\"bar\\">bar</foo>"

  """

  @spec encode!(root :: Saxy.XML.element(), prolog :: Saxy.Prolog.t() | Keyword.t()) :: String.t()

  def encode!(root, prolog \\ []) do
    root
    |> Encoder.encode_to_iodata(prolog)
    |> IO.iodata_to_binary()
  end

  @doc """
  Encodes a simple form element into IO data.

  Same as `encode!/2` but this encodes the document into IO data.

  ## Examples

      iex> import Saxy.XML
      iex> root = element(:foo, [{"foo", "bar"}], "bar")
      iex> prolog = [version: "1.0"]
      iex> Saxy.encode_to_iodata!(root, prolog)
      [
        ['<?xml', [32, 'version', 61, 34, "1.0", 34], [], [], '?>'],
        [60, "foo", 32, "foo", 61, 34, "bar", 34],
        62,
        ["bar"],
        [60, 47, "foo", 62]
      ]

  """
  @spec encode_to_iodata!(root :: Saxy.XML.element(), prolog :: Saxy.Prolog.t() | Keyword.t()) :: iodata()

  def encode_to_iodata!(root, prolog \\ []) do
    Encoder.encode_to_iodata(root, prolog)
  end
end
