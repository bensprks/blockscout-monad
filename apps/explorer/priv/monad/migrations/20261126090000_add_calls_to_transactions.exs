# SPDX-License-Identifier: LicenseRef-Blockscout
# Added by the Monad fork on 2026-11-26. See MONAD.md.
defmodule Explorer.Repo.Monad.Migrations.AddCallsToTransactions do
  use Ecto.Migration

  def change do
    alter table(:transactions) do
      add(:calls, :jsonb, null: true)
    end
  end
end
