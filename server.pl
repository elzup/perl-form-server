#!/usr/bin/env perl
use strict;
use warnings;
use CGI;
use Data::Dumper;
use IO::Socket::INET;

my $PORT = 3010;

# HTTPサーバーを作成
my $server = IO::Socket::INET->new(
    LocalHost => '0.0.0.0',
    LocalPort => $PORT,
    Type      => SOCK_STREAM,
    Reuse     => 1,
    Listen    => 10
) or die "HTTPサーバーを起動できませんでした: $!";

print "サーバーを起動しました。http://localhost:$PORT/ にアクセスしてください\n";

# リクエストを処理
while (my $client = $server->accept()) {
    # HTTPリクエストを読み込む
    my $request = '';
    while (my $line = <$client>) {
        $request .= $line;
        last if $line eq "\r\n";
    }
    
    # リクエスト情報を解析
    my ($method, $path) = $request =~ m/^(\w+)\s+(\S+)/;
    my %headers;
    while ($request =~ m/^([^:\s]+):\s*([^\r\n]+)/mg) {
        $headers{$1} = $2;
    }
    
    # 環境変数を設定（CGIスクリプトのために）
    local $ENV{REQUEST_METHOD} = $method || '';
    local $ENV{CONTENT_TYPE} = $headers{'Content-Type'} || '';
    local $ENV{CONTENT_LENGTH} = $headers{'Content-Length'} || 0;
    
    # POSTリクエストの場合、ボディを読み込む
    my $post_data = '';
    if ($method eq 'POST' && $ENV{CONTENT_LENGTH} > 0) {
        print "POSTリクエストを処理します。Content-Length: " . $ENV{CONTENT_LENGTH} . "\n";
        print "Content-Type: " . $ENV{CONTENT_TYPE} . "\n";
        
        my $bytes_to_read = $ENV{CONTENT_LENGTH};
        my $buffer;
        while ($bytes_to_read > 0 && $client->read($buffer, $bytes_to_read)) {
            $post_data .= $buffer;
            $bytes_to_read -= length($buffer);
        }
        
        # デバッグ用：POSTデータの先頭部分を表示
        my $preview = substr($post_data, 0, 100);
        print "POSTデータ（先頭100バイト）: $preview\n";
    }
    
    # レスポンスを生成
    my $response = "HTTP/1.1 200 OK\r\n";
    $response .= "Content-Type: text/plain; charset=utf-8\r\n";
    $response .= "Connection: close\r\n";
    $response .= "\r\n";
    
    # CGIオブジェクトを作成（POSTデータを渡す）
    my $cgi;
    eval {
        if ($method eq 'POST' && $post_data) {
            print "CGIオブジェクトを作成します（POSTデータあり）\n";
            # STDINにPOSTデータを設定
            open my $fh, '<', \$post_data;
            local *STDIN = $fh;
            $cgi = CGI->new;
        } else {
            print "CGIオブジェクトを作成します（POSTデータなし）\n";
            $cgi = CGI->new;
        }
    };
    if ($@) {
        print "CGIオブジェクトの作成中にエラーが発生しました: $@\n";
        $response .= "CGIオブジェクトの作成中にエラーが発生しました: $@\n";
        $cgi = CGI->new;  # エラー時は空のCGIオブジェクトを作成
    }
    
    # リクエスト情報を表示
    $response .= "=== リクエスト情報 ===\n";
    $response .= "REQUEST_METHOD: " . $ENV{REQUEST_METHOD} . "\n";
    $response .= "CONTENT_TYPE: " . $ENV{CONTENT_TYPE} . "\n";
    $response .= "CONTENT_LENGTH: " . $ENV{CONTENT_LENGTH} . "\n\n";
    
    # フォームパラメータを取得して表示
    $response .= "=== フォームデータ ===\n";
    my @param_names;
    eval {
        @param_names = $cgi->param();
        print "パラメータ数: " . scalar(@param_names) . "\n";
    };
    if ($@) {
        print "パラメータ取得中にエラーが発生しました: $@\n";
        $response .= "パラメータ取得中にエラーが発生しました: $@\n";
        @param_names = ();
    }
    foreach my $name (@param_names) {
        my $value = $cgi->param($name);
        $response .= "パラメータ名: $name\n";
        $response .= "値: $value\n";
        
        # ファイルの場合は追加情報を表示
        if ($cgi->upload($name)) {
            my $filename = $cgi->upload($name);
            my $type = $cgi->uploadInfo($filename)->{'Content-Type'};
            $response .= "ファイル名: " . $cgi->param($name) . "\n";
            $response .= "Content-Type: $type\n";
            
            # ファイルの内容（バイナリファイルの場合は表示しない）
            if ($type =~ /^text\//) {
                my $fh = $cgi->upload($name);
                if ($fh) {
                    local $/;
                    my $content = <$fh>;
                    $response .= "ファイル内容:\n$content\n";
                }
            } else {
                $response .= "バイナリファイルのため内容は表示しません\n";
            }
        }
        $response .= "\n";
    }
    
    # 環境変数を表示
    $response .= "=== 環境変数 ===\n";
    $response .= Dumper(\%ENV);
    
    # レスポンスを送信
    print $client $response;
    
    # レスポンスをログにも出力（Dockerログで確認できるように）
    print "=== クライアントへのレスポンス ===\n";
    print $response;
    print "==============================\n";
    
    close $client;
}