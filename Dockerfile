# 使用するベースイメージ
FROM ruby:3.2.2

# 作業ディレクトリを作成
RUN mkdir /app

# 作業ディレクトリを指定
WORKDIR /app

# 必要なパッケージをインストール
RUN apt-get update -qq && \
    apt-get install -y default-mysql-client vim && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# GemfileとGemfile.lockを先にコピー
COPY Gemfile Gemfile.lock /app/

# bundlerのインストールとbundle installを実行
RUN gem install bundler && \
    bundle install

# その他のプロジェクトファイルをコピー
COPY . /app

# コマンドの実行
CMD ["rails", "server", "-b", "0.0.0.0", "-p", "3000"]
