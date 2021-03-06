defmodule Rx.Schedulable do
  @moduledoc false  # TODO: Write documentation for this module.
  # Think of these as micro-tasks within an existing process.

  defmacro __using__(_) do
    quote location: :keep do
      @behaviour Rx.Schedulable

      def terminate(_reason, _state), do: :ok

      defoverridable [terminate: 2]
    end
  end

  @callback init(args :: term) ::
    {:ok, state} |
    {:ok, state, timeout | :hibernate} |
    :ignore |
    {:stop, reason :: any} when state: any

  @callback handle_task(args :: term, state :: term) ::
    {:ok, new_state} |
    {:ok, new_state, opts} |
    {:stop, reason, new_state} |
    {:stop, reason, new_state} when new_state: term, reason: term, opts: [term]

  @callback terminate(reason, state :: term) ::
    term when reason: :normal | :shutdown | {:shutdown, term} | term
end
