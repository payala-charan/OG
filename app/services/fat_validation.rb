# frozen_string_literal: true

# Compares the FAT Overview screen with opportunity totals stored in OG.
# FAT is opened read-only in a local Chrome window. Nothing in this module
# writes FAT business data.
module FatValidation
  class Error < StandardError; end
  class ConfigurationError < Error; end
  class AuthenticationError < Error; end
  class BrowserError < Error; end
  class MissingReportError < Error; end
  class EmptyReportError < Error; end
  class ReadOnlyError < Error; end
  class ExcelNotConfigured < Error; end

  OPPORTUNITY_COLUMN = "opportunity"
end
