# frozen_string_literal: true

module DatabaseTransfer
  # Models that read tables a transfer created in OG.
  #
  # A transferred purchase_histories table is DatabaseTransfer::Models::PurchaseHistory.
  # The same class is also published at PurchaseHistory when that constant is
  # free. An application model that already owns the name is left in place.
  module Models
  end
end
