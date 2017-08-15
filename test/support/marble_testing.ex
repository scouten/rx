defmodule MarbleTesting do
  @moduledoc false

  defmacro __using__(_) do
    quote do
      import MarbleTesting, only: [cold: 1, cold: 2, run: 1]
      @compile {:inline, marbles: 2}

      defp marbles(marbles, options \\ []), do:
        MarbleTesting.parse_marbles(marbles, options)

      defp sub_marbles(marbles), do:
        MarbleTesting.parse_marbles_as_subscriptions(marbles)
    end
  end

  defmodule ColdObservable do
    @moduledoc false
    defstruct [:events]
  end

  @doc ~S"""
  Creates a cold observable for use in marble testing.

  This event takes a marble diagram (see `parse_marbles/2`) and returns a
  special instance of Rx.Observable which will generate the events for a
  transform stage to process at the specified (virtual) times.
  """
  def cold(marbles, options \\ []) do
    events = parse_marbles(marbles, options)
    %Rx.Observable{reversed_stages: [%__MODULE__.ColdObservable{events: events}]}
  end

  @doc ~S"""
  Runs a marble test.

  TODO: Write more docs.
  """
  def run(%Rx.Observable{reversed_stages: _stages} = _observable) do
    raise "not yet"
  end

  @doc ~S"""
  Converts a string containing a marble diagram of notifications into a sequence
  of expected notifications.

  Each character in a marble diagram represents 10 "units" of time, also known as
  a "frame." Characters are parsed as follows:

  * `-` or space: Nothing happens in this frame.
  * `|`: The observable terminates with `:done` status in this frame.
  * `^`: The observer subscribes at this time point. All notifications before this
    are ignored. Time begins at time zero at this point.
  * `(` and `)`: Groups multiple events such that they all occur at the same time.
  * Any other character: The observable generates a `:next` notification
    during this frame. The value is the character *unless* overridden by a
    corresponding entry in the `values` option.

  ## Options

  If provided, the `options` keyword list is interpreted as follows:

  * `values:` is a map which can be used to replace a single-character `:next`
    notification with any other value. See examples below.

  ## Examples

  Simplest case (without options):

  ```
  iex> MarbleTesting.parse_marbles("-------a---b---|")
  [
    { 70, :next, "a"},
    {110, :next, "b"},
    {150, :done}
  ]
  ```

  Using `values` option to replace placeholder values with real values:

  ```
  iex> MarbleTesting.parse_marbles("-------a---b---|",
  ...>                                         values: %{a: "ABC", b: "BCD"})
  [
    { 70, :next, "ABC"},
    {110, :next, "BCD"},
    {150, :done}
  ]
  ```

  Trailing spaces permitted:

  ```
  iex> MarbleTesting.parse_marbles("--a--b--|   ",
  ...>                                         values: %{a: "A", b: "B"})
  [
    {20, :next, "A"},
    {50, :next, "B"},
    {80, :done}
  ]
  ```

  Explicit subscription start point:

  ```
  iex> MarbleTesting.parse_marbles("---^---a---b---|",
  ...>                                         values: %{a: "A", b: "B"})
  [
    { 40, :next, "A"},
    { 80, :next, "B"},
    {120, :done}
  ]
  ```

  Marble string that ends with an error:

  ```
  iex> MarbleTesting.parse_marbles("-------a---b---#",
  ...>                                         values: %{a: "A", b: "B"},
  ...>                                         error: "omg error!")
  [
    { 70, :next, "A"},
    {110, :next, "B"},
    {150, :error, "omg error!"}
  ]
  ```

  Grouped values occur at the same time:

  ```
  iex> MarbleTesting.parse_marbles("---(abc)-e-")
  [
    {30, :next, "a"},
    {30, :next, "b"},
    {30, :next, "c"},
    {50, :next, "e"}
  ]
  ```
  """
  def parse_marbles(marbles, options \\ []) do
    if String.contains?(marbles, "!") do
      raise ArgumentError,
            ~S/conventional marble diagrams cannot have the unsubscription marker "!"/
    end

    values = Keyword.get(options, :values, %{})
    error = Keyword.get(options, :error, "error")
    acc = %{rnotifs: [], time: 0, values: values, error: error, in_group?: false}

    marbles
    |> String.codepoints()
    |> Enum.reduce(acc, &parse_marble_char/2)
    |> Map.get(:rnotifs)
    |> Enum.reverse()
  end

  defp parse_marble_char("-", acc), do: add_idle_marble(acc)
  defp parse_marble_char(" ", acc), do: add_idle_marble(acc)
  defp parse_marble_char("^", acc), do:
    maybe_advance_time(%{acc | rnotifs: [], time: 0})
  defp parse_marble_char("(", %{in_group?: false} = acc), do:
    %{acc | in_group?: true}
  defp parse_marble_char(")", %{in_group?: true} = acc), do:
    maybe_advance_time(%{acc | in_group?: false})
  defp parse_marble_char("|", acc), do: add_notif_marble(:done, acc)
  defp parse_marble_char("#", %{error: error} = acc), do:
    add_notif_marble(:error, error, acc)
  defp parse_marble_char(char, %{values: values} = acc), do:
    add_notif_marble(:next, Map.get(values, String.to_atom(char), char), acc)

  defp add_idle_marble(acc), do: maybe_advance_time(acc)

  defp add_notif_marble(:next, value, %{time: time} = acc), do:
    add_notif_marble({time, :next, value}, acc)
  defp add_notif_marble(:error, error, %{time: time} = acc), do:
    add_notif_marble({time, :error, error}, acc)
  defp add_notif_marble(:done, %{time: time} = acc), do:
    add_notif_marble({time, :done}, acc)

  defp add_notif_marble(notif, %{rnotifs: rnotifs} = acc), do:
    maybe_advance_time(%{acc | rnotifs: [notif | rnotifs]})

  @frame_time_factor 10

  defp maybe_advance_time(%{in_group?: true} = acc), do: acc
  defp maybe_advance_time(%{time: old_time, in_group?: false} = acc), do:
    %{acc | time: old_time + @frame_time_factor}

  @doc ~S"""
  Converts a string containing a marble diagram of subscription events into a
  map with the time of each event.

  Note that there can be no more than one each of subscription and unsubscription
  events.

  Each character in a marble diagram represents 10 "units" of time, also known as
  a "frame." Characters are parsed as follows:

  * `-` or space: Nothing happens in this frame.
  * `^`: The observer subscribes at this time point.
  * `!`: The observer unsubscribes at this time point.
  * `(` and `)`: Groups multiple events such that they all occur at the same time.
  * Any other character: Invalid.

  ## Examples

  Simplest case:

  ```
  iex> MarbleTesting.parse_marbles_as_subscriptions("---^---!-")
  %{subscribed_frame: 30, unsubscribed_frame: 70}
  ```

  Subscribe only:

  ```
  iex> MarbleTesting.parse_marbles_as_subscriptions("---^-")
  %{subscribed_frame: 30, unsubscribed_frame: nil}
  ```

  Subscribe followed immediately by unsubscribe:

  ```
  iex> MarbleTesting.parse_marbles_as_subscriptions("---(^!)-")
  %{subscribed_frame: 30, unsubscribed_frame: 30}
  ```
  """
  def parse_marbles_as_subscriptions(marbles) do
    acc = %{subscribed_frame: nil, unsubscribed_frame: nil, in_group?: false, time: 0}

    marbles
    |> String.codepoints()
    |> Enum.reduce(acc, &parse_subscription_marble/2)
    |> Map.drop([:in_group?, :time])
  end

  defp parse_subscription_marble("-", acc), do: add_idle_marble(acc)
  defp parse_subscription_marble(" ", acc), do: add_idle_marble(acc)
  defp parse_subscription_marble("^", %{subscribed_frame: time}) when time != nil, do:
    raise_duplicate_marble("subscription", "^")
  defp parse_subscription_marble("^", %{time: time} = acc), do:
    maybe_advance_time(%{acc | subscribed_frame: time})
  defp parse_subscription_marble("!", %{unsubscribed_frame: time}) when time != nil, do:
    raise_duplicate_marble("unsubscription", "!")
  defp parse_subscription_marble("!", %{time: time} = acc), do:
    maybe_advance_time(%{acc | unsubscribed_frame: time})
  defp parse_subscription_marble("(", %{in_group?: false} = acc), do:
    %{acc | in_group?: true}
  defp parse_subscription_marble(")", %{in_group?: true} = acc), do:
    maybe_advance_time(%{acc | in_group?: false})
  defp parse_subscription_marble(char, _acc), do:
    raise ArgumentError,
          ~s"found an invalid character '#{char}' in subscription marble diagram."

  defp raise_duplicate_marble(type, char) do
    raise ArgumentError,
          ~s"found a second #{type} point '#{char}' in a " <>
            "subscription marble diagram. There can only be one."
  end
end