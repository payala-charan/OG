class UploadedFile < ApplicationRecord
  has_one_attached :file
  #validates :file_name, :quarter, :category, :file, presence: true
  validates :file_name, presence: true, uniqueness: { message: "already exists. Please choose another name." }
  validates :quarter, presence: true
  validates :category, presence: true
  validates :file, presence: true

  QUARTERS = ["Quarter 1 2025", "Quarter 2 2025", "Quarter 3 2025", "Quarter 4 2024", "Global"].freeze
  CATEGORIES = ["Biosimilars", "Catalogs", "Crosswalks", "Pricings", "Others"].freeze
end
