FROM ruby:3.2

RUN mkdir /app
WORKDIR /app
RUN apt-get update -qq && apt-get install -y default-mysql-client
ADD Gemfile /app/Gemfile
ADD Gemfile.lock /app/Gemfile.lock
RUN gem update && \
    bundle install
ADD . /app

CMD ["rails", "server", "-b", "0.0.0.0", "-p", "3000"]
