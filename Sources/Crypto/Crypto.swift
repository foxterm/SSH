// FoxTerm | Crypto.swift
// Copyright (c) 2025-2026 foxterm.app
// Created by foxterm@foxmail.com

import Foundation
import libetos
import OpenSSL

public final class Crypto: Sendable {
    public static let shared: Crypto = .init()
    public static let openssl_version = OPENSSL_VERSION_STR
    init() {
        openssl_mem_tracker_init()
    }
}
