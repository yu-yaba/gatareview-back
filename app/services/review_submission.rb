# frozen_string_literal: true

# レビューの新規投稿。重複投稿と通信のやり直し（再送）をここでまとめて扱う。
#
# - 同じ投稿者の確認と保存は順番に行う。ログイン投稿は利用者の行、匿名投稿は授業の行を
#   ロックしてから確認・保存するので、同時に届いた投稿も1件ずつ処理される。
# - ログイン利用者の同じ授業への2件目は「すでに投稿済み」として保存しない。
#   最終的な保証は reviews(user_id, lecture_id) の一意インデックス。
# - 再送の扱い: 同じ投稿者（同じ利用者、または匿名どうし）が同じ授業に、フォームの全項目が
#   同じレビューを RETRY_WINDOW 以内に投稿済みなら、やり直しとみなして新しく作らずに
#   既存のレビューを返す。項目が1つでも違えば別の投稿として扱う。
class ReviewSubmission
  RETRY_WINDOW = 10.minutes

  # status: :created（新規作成） / :resubmitted（再送。既存のレビューを返す） / :invalid（保存しない）
  Result = Data.define(:review, :status)

  def initialize(lecture:, user:, attributes:)
    @lecture = lecture
    @user = user
    @attributes = attributes
  end

  def call
    DeadlockRetry.call { Review.transaction { submit } }
  rescue ActiveRecord::RecordNotUnique
    review = build_review
    review.errors.add(:base, :already_reviewed)
    Result.new(review: review, status: :invalid)
  end

  private

  def submit
    lock_submitter
    review = build_review
    previous = recent_reviews_by_submitter.find { |existing| existing.same_submission_as?(review) }
    return Result.new(review: previous, status: :resubmitted) if previous

    Result.new(review: review, status: review.save ? :created : :invalid)
  end

  def build_review
    review = @lecture.reviews.new(@attributes)
    review.user = @user
    review
  end

  # ロックを取ってから最初の読み取りを行うので、先に終わった投稿の結果が必ず見える。
  def lock_submitter
    if @user
      User.lock.find(@user.id)
    else
      Lecture.lock.find(@lecture.id)
    end
  end

  def recent_reviews_by_submitter
    Review.where(lecture_id: @lecture.id, user_id: @user&.id)
          .where(created_at: RETRY_WINDOW.ago..)
          .order(:id)
          .to_a
  end
end
