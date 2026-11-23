# SPDX-License-Identifier: LicenseRef-Blockscout
# Modified 2026-11-23: cover Monad universal transactions (type 0x40).
defmodule EthereumJSONRPC.TransactionTest do
  use ExUnit.Case, async: true

  doctest EthereumJSONRPC.Transaction

  alias EthereumJSONRPC.Transaction

  describe "to_elixir/1" do
    test "skips unsupported keys" do
      map = %{"key" => "value", "key1" => "value1"}

      assert %{ignore: :ignore} = Transaction.to_elixir(map)
    end
  end

  describe "elixir_to_params/1" do
    test "adds compatibility defaults to minimal PostExec transactions only on OP Stack chains" do
      transaction = %{
        "blockHash" => "0xab6dfcf5ad132602e939db5f84f56945b1be4e136daab002f9bf9ff0c7f9f7a5",
        "blockNumber" => 27,
        "gas" => 0,
        "hash" => "0x39ee8fea8d4e719a75a5d64a4d5e34bdbd62f2543c88d00d0f00f91c8f1d8a20",
        "input" => "0xc3011b80",
        "transactionIndex" => 17,
        "type" => 0x7D,
        "value" => 0
      }

      if Application.get_env(:explorer, :chain_type) == :optimism do
        assert Transaction.elixir_to_params(transaction) == %{
                 block_hash: "0xab6dfcf5ad132602e939db5f84f56945b1be4e136daab002f9bf9ff0c7f9f7a5",
                 block_number: 27,
                 from_address_hash: "0x0000000000000000000000000000000000000000",
                 gas: 0,
                 gas_price: 0,
                 hash: "0x39ee8fea8d4e719a75a5d64a4d5e34bdbd62f2543c88d00d0f00f91c8f1d8a20",
                 index: 17,
                 input: "0xc3011b80",
                 nonce: 0,
                 r: 0,
                 s: 0,
                 to_address_hash: nil,
                 transaction_index: 17,
                 type: 0x7D,
                 v: 0,
                 value: 0
               }
      else
        assert_raise FunctionClauseError, fn -> Transaction.elixir_to_params(transaction) end
      end
    end

    test "preserves standard fields for type 0x7D transactions" do
      authorization_list = [%{"address" => "0x0000000000000000000000000000000000000001", "nonce" => 1}]

      assert %{
               created_contract_address_hash: "0x0000000000000000000000000000000000000002",
               from_address_hash: "0x0000000000000000000000000000000000000003",
               max_fee_per_gas: 30,
               max_priority_fee_per_gas: 2,
               authorization_list: ^authorization_list,
               type: 0x7D
             } =
               Transaction.elixir_to_params(%{
                 "authorizationList" => authorization_list,
                 "blockHash" => "0xab6dfcf5ad132602e939db5f84f56945b1be4e136daab002f9bf9ff0c7f9f7a5",
                 "blockNumber" => 27,
                 "creates" => "0x0000000000000000000000000000000000000002",
                 "from" => "0x0000000000000000000000000000000000000003",
                 "gas" => 21_000,
                 "gasPrice" => 10,
                 "hash" => "0x39ee8fea8d4e719a75a5d64a4d5e34bdbd62f2543c88d00d0f00f91c8f1d8a20",
                 "input" => "0x",
                 "maxFeePerGas" => 30,
                 "maxPriorityFeePerGas" => 2,
                 "nonce" => 1,
                 "transactionIndex" => 17,
                 "type" => 0x7D,
                 "value" => 1
               })
    end

    # Response of the Monad devnet (chain 20143) for block 34300. Unlike type 0x2, there is no "accessList" key.
    test "parses a Monad universal transaction (type 0x40) like an EIP-1559 one" do
      transaction =
        Transaction.to_elixir(%{
          "type" => "0x40",
          "chainId" => "0x4eaf",
          "nonce" => "0x0",
          "gas" => "0x5208",
          "maxPriorityFeePerGas" => "0x77359400",
          "maxFeePerGas" => "0x2f08236400",
          "to" => "0x680f7baa6156aa443f32d9912f605d351e5baa6b",
          "value" => "0x0",
          "input" => "0x",
          "r" => "0x956a9f66ca2c5be36a2b095096ec3eb304cfa8f8e99b010e82403f3d7f2224a5",
          "s" => "0x432b82d0f74cef268f95fe02913ebbc2159ad3a96035f918a92c0c8ecc00674",
          "yParity" => "0x1",
          "v" => "0x1",
          "hash" => "0x4a997475942d8e33530b510211c8e520aee6fb2abdcb73a2be7c4ed5ae7663f8",
          "blockHash" => "0x732bd812fae326c597b231d67fe41247c03a4ea753d26985a8606c96f121f6db",
          "blockNumber" => "0x85fc",
          "transactionIndex" => "0x0",
          "from" => "0x680f7baa6156aa443f32d9912f605d351e5baa6b",
          "gasPrice" => "0x17bfac7c00",
          "blockTimestamp" => "0x6af78caa"
        })

      assert %{
               block_hash: "0x732bd812fae326c597b231d67fe41247c03a4ea753d26985a8606c96f121f6db",
               block_number: 34_300,
               from_address_hash: "0x680f7baa6156aa443f32d9912f605d351e5baa6b",
               gas: 21_000,
               gas_price: 102_000_000_000,
               hash: "0x4a997475942d8e33530b510211c8e520aee6fb2abdcb73a2be7c4ed5ae7663f8",
               index: 0,
               input: "0x",
               max_fee_per_gas: 202_000_000_000,
               max_priority_fee_per_gas: 2_000_000_000,
               nonce: 0,
               r: 0x956A9F66CA2C5BE36A2B095096EC3EB304CFA8F8E99B010E82403F3D7F2224A5,
               s: 0x432B82D0F74CEF268F95FE02913EBBC2159AD3A96035F918A92C0C8ECC00674,
               to_address_hash: "0x680f7baa6156aa443f32d9912f605d351e5baa6b",
               type: 0x40,
               v: 1,
               value: 0
             } = Transaction.elixir_to_params(transaction)
    end
  end
end
