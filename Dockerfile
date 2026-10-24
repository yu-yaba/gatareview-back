# 使用するベースイメージ
FROM ruby:3.4.12

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
RUN gem install bundler -v 2.6.9 --no-document && \
    bundle _2.6.9_ install

# その他のプロジェクトファイルをコピー
COPY . /app

COPY entrypoint.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/entrypoint.sh
ENTRYPOINT ["entrypoint.sh"]

# コマンドの実行
CMD ["rails", "server", "-b", "0.0.0.0", "-p", "3000"]
