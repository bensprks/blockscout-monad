# SPDX-License-Identifier: LicenseRef-Blockscout
# Added by the Monad fork on 2026-11-26. See MONAD.md.
defmodule Explorer.Chain.Transaction.StateChangeTest do
  use Explorer.DataCase

  alias Explorer.Chain.{Hash, Wei}
  alias Explorer.Chain.Transaction.StateChange

  if Application.compile_env(:explorer, :chain_type) == :monad do
    @call %{"to" => "0x0000000000000000000000000000000000000001", "value" => 1, "input" => "0x"}

    # 21000 gas at a price of 2 wei
    @fee 42_000

    defp batch_transaction(calls, recipient) do
      block = insert(:block)

      :transaction
      |> insert(to_address: recipient, value: 3, gas_price: 2, calls: calls)
      |> with_block(block, gas_used: 21_000, status: :ok)
      |> Repo.preload(:block)
    end

    defp wei(value), do: %Wei{value: Decimal.new(value)}

    describe "from_loss/1" do
      test "is the fee alone for a batch, whose calls move the value as internal transactions" do
        transaction = batch_transaction([@call, %{@call | "value" => 2}], insert(:address))

        assert StateChange.from_loss(transaction) == wei(@fee)
      end

      test "is the value and the fee for a single call" do
        transaction = batch_transaction([%{@call | "value" => 3}], insert(:address))

        assert StateChange.from_loss(transaction) == wei(@fee + 3)
      end
    end

    describe "update_coin_balances_from_transaction/3" do
      test "moves the value of a batch once, through its internal transactions" do
        first = insert(:address)
        second = insert(:address)

        calls = [
          %{"to" => to_string(first.hash), "value" => 1, "input" => "0x"},
          %{"to" => to_string(second.hash), "value" => 2, "input" => "0x"}
        ]

        transaction = batch_transaction(calls, first)
        sender_hash = transaction.from_address_hash

        internal_transactions =
          for {to, value, index} <- [{first, 1, 1}, {second, 2, 2}] do
            build(:internal_transaction,
              transaction: transaction,
              call_type: :call,
              from_address_hash: sender_hash,
              to_address_hash: to.hash,
              value: wei(value),
              index: index,
              block_number: transaction.block_number,
              transaction_index: transaction.index
            )
          end

        transaction = %{transaction | internal_transactions: internal_transactions}

        balances =
          Map.new([sender_hash, first.hash, second.hash, transaction.block.miner_hash], fn hash ->
            {hash, {nil, wei(1_000_000)}}
          end)

        after_transaction =
          StateChange.update_coin_balances_from_transaction(balances, transaction, transaction.block)

        balance = fn %Hash{} = hash -> after_transaction |> Map.fetch!(hash) |> elem(1) end

        assert balance.(sender_hash) == wei(1_000_000 - @fee - 3)
        assert balance.(first.hash) == wei(1_000_001)
        assert balance.(second.hash) == wei(1_000_002)
      end
    end
  end
end
