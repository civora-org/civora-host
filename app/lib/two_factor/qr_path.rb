# frozen_string_literal: true

require "rqrcode_core"

module TwoFactor
  # Turns a provisioning URI into the geometry of an inline SVG QR code: the
  # view draws one <path>, so no markup is built from strings or marked raw.
  module QrPath
    QUIET_ZONE = 4 # modules of white border the QR specification asks for

    module_function

    # Returns { size:, d: } where size is the viewBox edge and d the path data.
    def call(uri)
      qr = RQRCodeCore::QRCode.new(uri, level: :m)
      segments = []
      qr.modules.each_with_index do |row, y|
        x = 0
        while x < row.length
          if row[x]
            start = x
            x += 1 while x < row.length && row[x]
            segments << "M#{start + QUIET_ZONE} #{y + QUIET_ZONE}h#{x - start}v1h-#{x - start}z"
          else
            x += 1
          end
        end
      end
      { size: qr.module_count + (2 * QUIET_ZONE), d: segments.join }
    end
  end
end
