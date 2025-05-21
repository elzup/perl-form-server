FROM perl:5.34

WORKDIR /app

# 必要なPerlモジュールをインストール
RUN cpanm CGI Data::Dumper

# サーバースクリプトをコピー
COPY server.pl /app/

# 実行権限を付与
RUN chmod +x /app/server.pl

# ポート3010を公開
EXPOSE 3010

# サーバーを起動
CMD ["perl", "server.pl"]