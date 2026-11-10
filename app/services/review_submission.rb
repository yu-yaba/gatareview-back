# frozen_string_literal: true

# レビューの新規投稿。重複投稿と通信のやり直し（再送）をここでまとめて扱う。
#
# - ログイン投稿は利用者の行をロックしてから確認・保存するので、同じ利用者の同時投稿は
#   1件ずつ処理され、同じ授業への2件目は「すでに投稿済み」として保存しない。
#   最終的な保証は reviews(user_id, lecture_id) の一意インデックス。
# - 再送の扱い: ログイン利用者が同じ授業に、フォームの全項目が同じレビューを RETRY_WINDOW 以内に
#   投稿済みなら、やり直しとみなして新しく作らずに本人のそのレビューを返す。
# - 匿名投稿は再送としてまとめない。匿名どうしをまとめると、公開中のレビュー本文を匿名で送り直す
#   だけで、そのレビューが匿名投稿かログイン投稿かを見分けられてしまうため。
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
    review = build_review(@user)
    review.errors.add(:base, :already_reviewed)
    Result.new(review: review, status: :invalid)
  end

  private

  def submit
    user = lock_user
    review = build_review(user)
    previous = user && previous_identical_review(user, review)
    return Result.new(review: previous, status: :resubmitted) if previous

    Result.new(review: review, status: review.save ? :created : :invalid)
  end

  # ロックを取ってから最初の読み取りを行うので、先に終わった投稿の結果が必ず見える。
  # ロック時に読み直した利用者をレビューに結び付けるので、デッドロックでやり直しても
  # reviews_count を前回の試行の分まで数えない。
  def lock_user
    User.lock.find(@user.id) if @user
  end

  def build_review(user)
    review = @lecture.reviews.new(@attributes)
    review.user = user
    review
  end

  def previous_identical_review(user, review)
    user.reviews.where(lecture_id: @lecture.id, created_at: RETRY_WINDOW.ago..)
        .order(:id)
        .find { |existing| existing.same_submission_as?(review) }
  end
end
