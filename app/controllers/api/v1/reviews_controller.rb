class Api::V1::ReviewsController < ApplicationController
  before_action :set_lecture, except: [:total]

  def index
    reviews = @lecture.reviews
    render json: reviews
  end

  def create
    @review = @lecture.reviews.new(review_params)

    if @review.save
      render json: @review, status: :created
    else
      render json: @review.errors, status: :unprocessable_entity
    end
  end

  def total
    total_reviews = Review.count
    render json: { count: total_reviews }
  end

  private

  def set_lecture
    @lecture = Lecture.find(params[:lecture_id])
  end

  def review_params
    params.require(:review).permit(:rating, :content, :period_year, :period_term, :textbook, :attendance,
                                   :grading_type, :content_difficulty, :content_quality)
  end
end
