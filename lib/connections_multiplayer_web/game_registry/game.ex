defmodule ConnectionsMultiplayerWeb.GameRegistry.Game do
  @type t :: %__MODULE__{
          id: String.t(),
          pid: pid()
        }

  use Memento.Table, attributes: [:id, :pid]
end
