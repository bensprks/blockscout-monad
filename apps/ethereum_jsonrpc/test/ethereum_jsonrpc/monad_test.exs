# SPDX-License-Identifier: LicenseRef-Blockscout
# Added by the Monad fork on 2026-11-26. See MONAD.md.
defmodule EthereumJSONRPC.MonadTest do
  use ExUnit.Case, async: true

  use Utils.CompileTimeEnvHelper, chain_type: [:explorer, :chain_type]

  alias EthereumJSONRPC.Transaction

  if @chain_type == :monad do
    @created_contract_address_hash "0xe69a847cd5bc0c9480ada0b339d7f0a8cac2b667"
    @creation_input "0x6014600c60003960146000f36000358060ff14600e57600055005b60006000fd"

    # Response of the Monad devnet (chain 20143) for a transaction in block 2009316: one call that
    # creates a contract, then two calls to it. The node nulls `to`, `value` and `input`.
    defp universal_transaction(overrides \\ %{}) do
      Map.merge(
        %{
          "type" => "0x40",
          "chainId" => "0x4eaf",
          "nonce" => "0xb",
          "gas" => "0x1fff9",
          "maxPriorityFeePerGas" => "0x77359400",
          "maxFeePerGas" => "0x2f08236400",
          "to" => nil,
          "value" => "0x0",
          "input" => "0x",
          "calls" => [
            %{"to" => nil, "value" => "0x0", "input" => @creation_input},
            %{
              "to" => @created_contract_address_hash,
              "value" => "0x0",
              "input" => "0x0000000000000000000000000000000000000000000000000000000000000001"
            },
            %{
              "to" => @created_contract_address_hash,
              "value" => "0x0",
              "input" => "0x0000000000000000000000000000000000000000000000000000000000000002"
            }
          ],
          "r" => "0xe5ce35eb9811c5d17e186e11600c0799d9a4719a713c80a4a371239b37b71282",
          "s" => "0x6c3aaf73852f64f79198e1dce37d56a4160d29802c4fbf2985cc66c04c5b367e",
          "yParity" => "0x1",
          "v" => "0x1",
          "hash" => "0x85d0c6248d284c88298fcae85141ea77594f855d22ff62f7884ca465feae5ab9",
          "blockHash" => "0x5b0801f5ec22edf7fd7e63fa9fb1a8724f56080f306f28a8341f7efe63211659",
          "blockNumber" => "0x1ea8e4",
          "transactionIndex" => "0x0",
          "from" => "0x7e5f4552091a69125d5dfcb7b8c2659029395bdf",
          "gasPrice" => "0x17bfac7c00",
          "blockTimestamp" => "0x6b074e2d",
          "accessList" => [],
          "authorizationList" => []
        },
        overrides
      )
    end

    defp params(overrides \\ %{}) do
      overrides
      |> universal_transaction()
      |> Transaction.to_elixir()
      |> Transaction.elixir_to_params()
    end

    describe "Transaction.elixir_to_params/1" do
      test "keeps the calls of a batch and derives `to` and `input` from the first one" do
        assert %{
                 type: 64,
                 gas: 131_065,
                 to_address_hash: nil,
                 input: @creation_input,
                 value: 0,
                 calls: [
                   %{"to" => nil, "value" => 0, "input" => @creation_input},
                   %{"to" => @created_contract_address_hash, "value" => 0},
                   %{"to" => @created_contract_address_hash, "value" => 0}
                 ]
               } = params()
      end

      test "addresses a batch of plain calls to the first recipient and sums the values" do
        first = "0x3dc46eb55d472b326b634ec90baf2bdc7edc1009"
        second = "0x0000000000000000000000000000000000000001"

        calls = [
          %{"to" => first, "value" => "0x1", "input" => "0x1234"},
          %{"to" => second, "value" => "0x2", "input" => "0xabcd"}
        ]

        assert %{to_address_hash: ^first, input: "0x1234", value: 3} = params(%{"calls" => calls})
      end

      test "leaves a single call as the node reports it" do
        to = "0x680f7baa6156aa443f32d9912f605d351e5baa6b"

        assert %{to_address_hash: ^to, input: "0x", value: 5, calls: [%{"to" => ^to, "value" => 5}]} =
                 params(%{"to" => to, "value" => "0x5", "calls" => [%{"to" => to, "value" => "0x5", "input" => "0x"}]})
      end

      test "leaves a response without calls as it is" do
        to = "0x680f7baa6156aa443f32d9912f605d351e5baa6b"

        params =
          %{"to" => to, "value" => "0x5"}
          |> universal_transaction()
          |> Map.delete("calls")
          |> Transaction.to_elixir()
          |> Transaction.elixir_to_params()

        assert %{to_address_hash: ^to, value: 5} = params
        refute Map.has_key?(params, :calls)
      end

      test "leaves the transactions of other types untouched" do
        to = "0x680f7baa6156aa443f32d9912f605d351e5baa6b"

        params =
          %{"type" => "0x2", "to" => to, "value" => "0x1"}
          |> universal_transaction()
          |> Map.delete("calls")
          |> Transaction.to_elixir()
          |> Transaction.elixir_to_params()

        assert %{type: 2, to_address_hash: ^to, value: 1} = params
        refute Map.has_key?(params, :calls)
      end
    end
  end
end
