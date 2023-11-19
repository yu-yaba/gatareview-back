class Api::V1::LecturesController < ApplicationController
  before_action :set_lecture, only: [:show, :create_image, :show_image]

  def index
    query_conditions = {}

    if params[:faculty].present?
      query_conditions[:faculty] = params[:faculty]
    end

    if params[:searchWord].present?
      query_conditions[:title] = params[:searchWord]
    end

    if query_conditions.empty?
      render json: { error: 'Either faculty or searchWord must be specified.' }, status: 400
      return
    end

    @lectures = Lecture.all
      .where("faculty LIKE :faculty OR title LIKE :searchWord", faculty: "%#{query_conditions[:faculty]}%", searchWord: "%#{query_conditions[:title]}%")

    lecture_ids = @lectures.pluck(:id)
    avg_ratings = Review.where(lecture_id: lecture_ids).group(:lecture_id).average(:rating)

    @lectures_json = @lectures.map do |lecture|
      lecture_attributes = lecture.attributes
      avg_rating = avg_ratings[lecture.id.to_s] || 0
      lecture_attributes[:avg_rating] = avg_rating.round(1)
      lecture_attributes
    end

    render json: @lectures_json
  end


  def show
    @lecture = Lecture.with_attached_images.includes(:reviews).find(params[:id])
    if @lecture.nil?
      render json: { error: 'Lecture not found' }, status: 404
      return
    end
  
    if @lecture.images.attached?
      render json: @lecture.as_json.merge({ image_url: rails_blob_url(@lecture.image) })
    else
      render json: @lecture.as_json
    end
  end
    

  def create
    normalized_title = lecture_params[:title].strip.downcase
    normalized_lecturer = lecture_params[:lecturer].strip.downcase
    normalized_faculty = lecture_params[:faculty].strip.downcase

    duplicate_lecture = Lecture.find_by(title: normalized_title, lecturer: normalized_lecturer, faculty: normalized_faculty)

    if duplicate_lecture
      render json: { error: 'A similar lecture already exists' }, status: :unprocessable_entity
      return
    end

    @lecture = Lecture.new(lecture_params)

    if @lecture.save
      render json: @lecture, status: :created
    else
      render json: @lecture.errors, status: :unprocessable_entity
    end
  end


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
