// FoxTerm | Crypto.swift
// Copyright (c) 2025-2026 foxterm.app
// Created by foxterm@foxmail.com

import Foundation
import OpenSSL

public final class Crypto: Sendable {
    public static let shared: Crypto = .init()
    public static let openssl_version = OPENSSL_VERSION_STR
}
