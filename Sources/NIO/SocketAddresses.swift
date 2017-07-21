//===----------------------------------------------------------------------===//
//
// This source file is part of the SwiftNIO open source project
//
// Copyright (c) 2017-2018 Apple Inc. and the SwiftNIO project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of SwiftNIO project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import Foundation

#if os(macOS) || os(iOS) || os(tvOS) || os(watchOS)
    import Darwin
#elseif os(Linux)
    import Glibc
#endif

public enum SocketAddressError: Error {
    case unknown
    case unsupported
}

private extension UInt16 {
    /* this takes an UInt16 in big-endian representation and converts it to
     whatever endianness the we're running on. It does work for both big
     and little endian machines.
     Cf. https://commandcenter.blogspot.co.uk/2012/04/byte-order-fallacy.html
     */
    static func from(bigEndian input: UInt16) -> UInt16 {
        var val: UInt16 = input
        return withUnsafePointer(to: &val) { (ptr: UnsafePointer<UInt16>) -> UInt16 in
            ptr.withMemoryRebound(to: UInt8.self, capacity: MemoryLayout<UInt16>.size) { data in
                var result: UInt16 = 0
                result |= (UInt16(data[1]))
                result |= (UInt16(data[0]) << 8)
                return result
            }
        }
    }
}

public enum SocketAddress: CustomStringConvertible {
    case v4(address: sockaddr_in, host: String)
    case v6(address: sockaddr_in6, host: String)

    public var description: String {
        let port: UInt16
        let host: String
        let type: String
        switch self {
        case .v4(address: let addr, host: let h):
            host = h
            type = "IPv4"
            port = UInt16.from(bigEndian: addr.sin_port)
        case .v6(address: let addr, host: let h):
            host = h
            type = "IPv6"
            port = UInt16.from(bigEndian: addr.sin6_port)
        }
        return "[\(type)]\(host):\(port)"
    }
    
    public init(IPv4Address addr: sockaddr_in, host: String) {
        self = .v4(address: addr, host: host)
    }

    public init(IPv6Address addr: sockaddr_in6, host: String) {
        self = .v6(address: addr, host: host)
    }

    public static func newAddressResolving(host: String, port: Int32) throws -> SocketAddress {
        var info: UnsafeMutablePointer<addrinfo>?
        
        /* FIXME: this is blocking! */
        if getaddrinfo(host, String(port), nil, &info) != 0 {
            // TODO: May may be able to return a bit more info to the caller. Let us just keep it simple for now
            throw SocketAddressError.unknown
        }
        
        defer {
            if info != nil {
                freeaddrinfo(info)
            }
        }
        
        if let info = info {
            switch info.pointee.ai_family {
            case AF_INET:
                return info.pointee.ai_addr.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { ptr in
                    return .v4(address: ptr.pointee, host: host)
                }
            case AF_INET6:
                return info.pointee.ai_addr.withMemoryRebound(to: sockaddr_in6.self, capacity: 1) { ptr in
                    return .v6(address: ptr.pointee, host: host)
                }
            default:
                throw SocketAddressError.unsupported
            }
        } else {
            /* this is odd, getaddrinfo returned NULL */
            throw SocketAddressError.unsupported
        }
    }

}

