# SPDX-License-Identifier: LicenseRef-Blockscout
# Added by the Monad fork on 2026-11-26. See MONAD.md.
defmodule BlockScoutWeb.API.V2.MonadView do
  @moduledoc """
  View functions for rendering Monad-related data in JSON format.
  """
  use Utils.CompileTimeEnvHelper, chain_type: [:explorer, :chain_type]

  if @chain_type == :monad do
    alias Explorer.Chain.{Address, Transaction}

    @doc """
    Extends the JSON output with the calls of a universal transaction: their number, and for a
    single transaction their ordered list.

    Both fields are `nil` for the transactions of other types. As with the token transfers, the
    calls are rendered for a single transaction only to keep the list responses small. The number
    is always there: the `to` and the `value` of a transaction with more than one call are derived
    from all of its calls, so a client must not read them as one transfer to one recipient.

    ## Parameters
    - `out_json`: A map defining the output JSON which will be extended.
    - `transaction`: The transaction structure.
    - `single_transaction?`: A boolean indicating if it is a single transaction.

    ## Returns
    - A map extended with the data related to Monad.
    """
    @spec extend_transaction_json_response(map(), Transaction.t(), boolean()) :: map()
    def extend_transaction_json_response(out_json, %Transaction{calls: calls}, single_transaction?)
        when is_list(calls) do
      out_json
      |> Map.put("calls_count", length(calls))
      |> Map.put("calls", if(single_transaction?, do: Enum.map(calls, &prepare_call/1)))
    end

    def extend_transaction_json_response(out_json, %Transaction{}, _single_transaction?) do
      out_json
      |> Map.put("calls_count", nil)
      |> Map.put("calls", nil)
    end

    # A call is stored as it comes from the JSON RPC response: `to` is a plain address string which
    # is `nil` for a contract creation call, `value` is an integer and `input` is a hex string.
    # Renders it the way the rest of the API v2 renders those types: a checksummed address and a
    # stringified value.
    @spec prepare_call(map()) :: map()
    defp prepare_call(call) do
      %{
        "to" => call |> Map.get("to") |> checksum_or_nil(),
        "value" => (Map.get(call, "value") || 0) |> to_string(),
        "input" => Map.get(call, "input") || "0x"
      }
    end

    @spec checksum_or_nil(String.t() | nil) :: String.t() | nil
    defp checksum_or_nil(nil), do: nil
    defp checksum_or_nil(address_hash_string), do: Address.checksum(address_hash_string)
  else
    def extend_transaction_json_response(out_json, _, _), do: out_json
  end
end
