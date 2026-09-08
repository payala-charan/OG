class PricingCatalogsController < ApplicationController
	def pricing_catalog_bulk_upload
	  file = params[:pricing_catalog][:file]
	  return redirect_back(fallback_location: root_path, alert: "No file uploaded") unless file.present?

	  upload = PricingCatalogUpload.create!

	  upload.file.attach(
	    io: file,
	    filename: file.original_filename,
	    content_type: file.content_type
	  )

	  if upload.file.attached?
	    PricingCatalogParseJob.perform_now(upload.id)
	    redirect_back(fallback_location: root_path, notice: "File uploaded successfully. Processing in background...")
	  else
	    redirect_back(fallback_location: root_path, alert: "File upload failed.")
	  end
	end
end
