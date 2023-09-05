class Api::V2::LecturesController < ApplicationController
  before_action :set_lecture, only: [:show, :create_image, :show_image]

# GET /lectures
  def index
    @lectures = Lecture.with_attached_images.includes(:reviews).page(params[:page]).per(params[:limit])

    @lectures_json = @lectures.map do |lecture|
      lecture_attributes = lecture.attributes
      lecture_attributes[:avg_rating] = lecture.reviews.average(:rating)&.round(1) || 0
      lecture_attributes[:image_urls] = lecture.images.map { |image| url_for(image) }
      lecture_attributes
    end

    render json: @lectures_json
  end

  # GET /lectures/1
  def show
    if @lecture.image.attached?
      render json: @lecture.as_json.merge({ image_url: rails_blob_url(@lecture.image) })
    else
      render json: { error: 'No image attached' }, status: 404
    end
  end

  # POST /lectures
  def create
    @lecture = Lecture.new(lecture_params)

    if @lecture.save
      render json: @lecture, status: :created
    else
      render json: @lecture.errors, status: :unprocessable_entity
    end
  end

  # POST /lectures/1/images
  def create_image
    if params[:lecture][:image]
      @lecture.images.attach(params[:lecture][:image])
      render json: @lecture, status: :created
    else
      render json: { error: 'No image provided' }, status: :unprocessable_entity
    end
  end
      
  def show_image
    if @lecture.images.attached?
      images = @lecture.images.map do |image|
        {
          url: rails_blob_url(image),
          type: image.blob.content_type
        }
      end
      render json: { images: images }
    else
      render json: { error: 'No image attached' }, status: 404
    end
  end
      

    private
    def set_lecture
      @lecture = Lecture.find(params[:id])
    end

    def lecture_params
      params.require(:lecture).permit(:title, :lecturer, :faculty, :image)
    end
end
