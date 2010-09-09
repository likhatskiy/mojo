#!/usr/bin/env perl

use strict;
use warnings;

# Disable epoll, kqueue and IPv6
BEGIN { $ENV{MOJO_POLL} = $ENV{MOJO_NO_IPV6} = 1 }

use Mojo::IOLoop;
use Test::More;

# Make sure sockets are working
plan skip_all => 'working sockets required for this test!'
  unless Mojo::IOLoop->new->generate_port;
plan tests => 825;

use_ok('Mojo::Client');

# The strong must protect the sweet.
use Mojolicious::Lite;

# Silence
app->log->level('fatal');

# GET /
get '/' => {text => 'works'};

my $client = Mojo::Client->singleton->app(app);

# Server
my $port   = $client->ioloop->generate_port;
my $buffer = {};
my $last;
$client->ioloop->listen(
    port      => $port,
    accept_cb => sub {
        my ($loop, $id) = @_;
        $last = $id;
        $buffer->{$id} = '';
    },
    read_cb => sub {
        my ($loop, $id, $chunk) = @_;
        $buffer->{$id} .= $chunk;
        if (index $buffer->{$id}, "\x0d\x0a\x0d\x0a") {
            delete $buffer->{$id};
            $loop->write($id => "HTTP/1.1 200 OK\x0d\x0a"
                  . "Connection: keep-alive\x0d\x0a"
                  . "Content-Length: 6\x0d\x0a\x0d\x0aworks!");
        }
    },
    error_cb => sub {
        my ($self, $id) = @_;
        delete $buffer->{$id};
    }
);

# GET /
my $tx = $client->get('/');
ok($tx->success, 'successful');
is($tx->res->code, 200,     'right status');
is($tx->res->body, 'works', 'right content');

# GET / (mock server)
$tx = $client->get("http://localhost:$port/mock");
ok($tx->success, 'successful');
is($tx->kept_alive, undef,    'kept connection not alive');
is($tx->res->code,  200,      'right status');
is($tx->res->body,  'works!', 'no content');

# GET / (mock server again)
$tx = $client->get("http://localhost:$port/mock");
ok($tx->success, 'successful');
is($tx->kept_alive, 1,        'kept connection alive');
is($tx->res->code,  200,      'right status');
is($tx->res->body,  'works!', 'no content');

# GET / (close connection)
$client->get(
    "http://localhost:$port/mock" => sub { shift->ioloop->drop($last) })
  ->process;

# GET / (mock server closed connection)
$tx = $client->get("http://localhost:$port/mock");
ok($tx->success, 'successful');
is($tx->kept_alive, undef,    'kept connection not alive');
is($tx->res->code,  200,      'right status');
is($tx->res->body,  'works!', 'no content');

# GET / (mock server again)
$tx = $client->get("http://localhost:$port/mock");
ok($tx->success, 'successful');
is($tx->kept_alive, 1,        'kept connection alive');
is($tx->res->code,  200,      'right status');
is($tx->res->body,  'works!', 'no content');

# GET / (close connection)
$client->get(
    "http://localhost:$port/mock" => sub { shift->ioloop->drop($last) })
  ->process;

# GET / (mock server closed connection)
$tx = $client->get("http://localhost:$port/mock");
ok($tx->success, 'successful');
is($tx->kept_alive, undef,    'kept connection not alive');
is($tx->res->code,  200,      'right status');
is($tx->res->body,  'works!', 'no content');

# Nested keep alive
my @kept_alive;
$client->async->get(
    '/',
    sub {
        my ($self, $tx) = @_;
        push @kept_alive, $tx->kept_alive;
        $self->async->get(
            '/',
            sub {
                my ($self, $tx) = @_;
                push @kept_alive, $tx->kept_alive;
                $self->async->get(
                    '/',
                    sub {
                        my ($self, $tx) = @_;
                        push @kept_alive, $tx->kept_alive;
                        $self->async->ioloop->stop;
                    }
                )->process;
            }
        )->process;
    }
)->process;
$client->async->ioloop->start;
is_deeply(\@kept_alive, [undef, 1, 1], 'connections kept alive');

# Stress test to make sure we don't leak file descriptors
for (1 .. 200) {
    my $tx = Mojo::Client->new->app(app)->get('/');
    is($tx->res->code, 200,     'right status');
    is($tx->res->body, 'works', 'right content');
    ok($tx->success, 'request successful');
    is($tx->kept_alive, undef, 'connection not kept alive');
}
