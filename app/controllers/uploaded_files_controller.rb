class UploadedFilesController < ApplicationController
  def index
    @files = UploadedFile.all.order(created_at: :desc)
  end

  DELETE_PASSWORD = "jaibabu"

  def create
    @file = UploadedFile.new(file_params)

    if UploadedFile.exists?(file_name: @file.file_name)
      flash[:alert] = " File name already exists. Please choose another file name."
    elsif @file.save
      flash[:notice] = " File uploaded successfully!"
    else
      flash[:alert] = "Failed to upload file. Please fill all fields."
    end

    redirect_to uploaded_files_path
  end

  def destroy
    file = UploadedFile.find(params[:id])
    file.destroy
    flash[:notice] = " File deleted successfully!"
    redirect_to uploaded_files_path
  end

  def delete_with_password
    if params[:password] != DELETE_PASSWORD
      flash[:alert] = "Incorrect password"
      return redirect_to uploaded_files_path
    end

    file = UploadedFile.find(params[:file_id])
    file.destroy

    flash[:notice] = "File deleted successfully!"
    redirect_to uploaded_files_path
  end


  private

  def file_params
    params.require(:uploaded_file).permit(:file_name, :quarter, :category, :file)
  end
end
