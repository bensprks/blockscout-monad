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

    defp traced(transaction, transfers) do
      internal_transactions =
        for {{to, value}, index} <- Enum.with_index(transfers, 1) do
          build(:internal_transaction,
            transaction: transaction,
            call_type: :call,
            from_address_hash: transaction.from_address_hash,
            to_address_hash: to.hash,
            value: wei(value),
            index: index,
            block_number: transaction.block_number,
            transaction_index: transaction.index
          )
        end

      %{transaction | internal_transactions: internal_transactions}
    end

    defp balances_after(transaction, addresses) do
      balances =
        Map.new([transaction.from_address_hash, transaction.block.miner_hash | Enum.map(addresses, & &1.hash)], fn
          hash -> {hash, {nil, wei(1_000_000)}}
        end)

      after_transaction =
        StateChange.update_coin_balances_from_transaction(balances, transaction, transaction.block)

      fn %Hash{} = hash -> after_transaction |> Map.fetch!(hash) |> elem(1) end
    end

    defp two_recipient_batch do
      first = insert(:address)
      second = insert(:address)

      calls = [
        %{"to" => to_string(first.hash), "value" => 1, "input" => "0x"},
        %{"to" => to_string(second.hash), "value" => 2, "input" => "0x"}
      ]

      {batch_transaction(calls, first), first, second}
    end

    describe "from_loss/1" do
      test "is the fee alone for a traced batch, whose calls move the value as internal transactions" do
        {transaction, first, second} = two_recipient_batch()

        assert transaction |> traced([{first, 1}, {second, 2}]) |> StateChange.from_loss() == wei(@fee)
      end

      test "is the value and the fee for a batch which is not traced yet" do
        {transaction, _first, _second} = two_recipient_batch()

        assert StateChange.from_loss(%{transaction | internal_transactions: []}) == wei(@fee + 3)
      end

      test "is the value and the fee for a single call" do
        transaction = batch_transaction([%{@call | "value" => 3}], insert(:address))

        assert StateChange.from_loss(%{transaction | internal_transactions: []}) == wei(@fee + 3)
      end
    end

    describe "update_coin_balances_from_transaction/3" do
      test "moves the value of a traced batch once, through its internal transactions" do
        {transaction, first, second} = two_recipient_batch()
        balance = transaction |> traced([{first, 1}, {second, 2}]) |> balances_after([first, second])

        assert balance.(transaction.from_address_hash) == wei(1_000_000 - @fee - 3)
        assert balance.(first.hash) == wei(1_000_001)
        assert balance.(second.hash) == wei(1_000_002)
      end

      test "moves the same value from the calls while the batch is not traced yet" do
        {transaction, first, second} = two_recipient_batch()
        balance = balances_after(%{transaction | internal_transactions: []}, [first, second])

        assert balance.(transaction.from_address_hash) == wei(1_000_000 - @fee - 3)
        assert balance.(first.hash) == wei(1_000_001)
        assert balance.(second.hash) == wei(1_000_002)
      end

      test "moves nothing but the fee for a failed batch" do
        {transaction, first, second} = two_recipient_batch()
        failed = %{transaction | status: :error, internal_transactions: []}
        balance = balances_after(failed, [first, second])

        assert balance.(transaction.from_address_hash) == wei(1_000_000 - @fee)
        assert balance.(first.hash) == wei(1_000_000)
        assert balance.(second.hash) == wei(1_000_000)
      end
    end
  end
end
