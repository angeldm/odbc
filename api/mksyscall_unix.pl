#!/usr/bin/perl
# Copyright 2012 The Go Authors. All rights reserved.
# Use of this source code is governed by a BSD-style
# license that can be found in the LICENSE file.

# This program is based on $GOROOT/src/pkg/syscall/mksyscall_windows.pl.

use strict;

my $cmdline = "mksyscall_unix.pl " . join(' ', @ARGV);
my $errors = 0;

binmode STDOUT;

if($ARGV[0] =~ /^-/) {
	print STDERR "usage: mksyscall_unix.pl [file ...]\n";
	exit 1;
}

sub parseparamlist($) {
	my ($list) = @_;
	$list =~ s/^\s*//;
	$list =~ s/\s*$//;
	if($list eq "") {
		return ();
	}
	return split(/\s*,\s*/, $list);
}

sub parseparam($) {
	my ($p) = @_;
	if($p !~ /^(\S*) (\S*)$/) {
		print STDERR "$ARGV:$.: malformed parameter: $p\n";
		$errors = 1;
		return ("xx", "int");
	}
	return ($1, $2);
}

my $package = "";
my $text = "";
while(<>) {
	chomp;
	s/\s+/ /g;
	s/^\s+//;
	s/\s+$//;
	$package = $1 if !$package && /^package (\S+)$/;
	next if !/^\/\/sys /;

	# Line must be of the form
	#	func Open(path string, mode int, perm int) (fd int, err error)
	# Split into name, in params, out params.
	if(!/^\/\/sys (\w+)\(([^()]*)\)\s*(?:\(([^()]+)\))?\s*(?:\[failretval(.*)\])?\s*(?:=\s*(?:(\w*)\.)?(\w*))?$/) {
		print STDERR "$ARGV:$.: malformed //sys declaration\n";
		$errors = 1;
		next;
	}
	my ($func, $in, $out, $failcond, $modname, $sysname) = ($1, $2, $3, $4, $5, $6);

	# Split argument lists on comma.
	my @in = parseparamlist($in);
	my @out = parseparamlist($out);

	# System call name.
	if($sysname eq "") {
		$sysname = "$func";
	}

	# Go function header.
	$out = join(', ', @out);
	if($out ne "") {
		$out = " ($out)";
	}
	if($text ne "") {
		$text .= "\n"
	}
	$text .= sprintf "func %s(%s)%s {\n", $func, join(', ', @in), $out;

	# Prepare arguments.
	my @sqlin= ();
	my @pin= ();
	foreach my $p (@in) {
		my ($name, $type) = parseparam($p);

		if($type =~ /^\*(SQLCHAR)/) {
			push @sqlin, sprintf "(*C.%s)(unsafe.Pointer(%s))", $1, $name;
		} elsif($type =~ /^\*(SQLWCHAR)/) {
			push @sqlin, sprintf "(*C.%s)(unsafe.Pointer(%s))", $1, $name;
		} elsif($type =~ /^\*(.*)$/) {
			push @sqlin, sprintf "(*C.%s)(%s)", $1, $name;
		} else {
			push @sqlin, sprintf "C.%s(%s)", $type, $name;
		}
		push @pin, sprintf "\"%s=\", %s, ", $name, $name;
	}

	$text .= sprintf "\tr := C.%s(%s)\n", $sysname, join(',', @sqlin);
	if(0) {
		$text .= sprintf "println(\"SYSCALL: %s(\", %s\") (\", r, \")\")\n", $func, join('", ", ', @pin);
	}
	$text .= "\treturn SQLRETURN(r)\n";
	$text .= "}\n";
}

if($errors) {
	exit 1;
}

print <<EOF;
// $cmdline
// MACHINE GENERATED BY THE COMMAND ABOVE; DO NOT EDIT

// Copyright 2012 The Go Authors. All rights reserved.
// Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

// +build linux
// +build cgo

package $package

import "unsafe"

// #cgo linux LDFLAGS: -lodbc
// #include <sql.h>
// #include <sqlext.h>
import "C"

$text

EOF
exit 0;
