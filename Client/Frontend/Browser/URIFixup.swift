/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import Foundation
import Shared

class URIFixup {
    
    // The entire point of punycoding is to convert UTF-8 characters to ASCII
    // Thus the resulting URL should be all ASCII characters *AND* valid URL allowed characters
    // Valid characters are defined in RFC 1808, and RFC 3492 specifies that punycoding:
    // "transforms a Unicode string into an ASCII string"
    // Why only the host/domain?.. according to RFC 3492 - IDNA Punycode,
    // only the DOMAIN is supposed to be punycoded and not the entire URL.
    // The rest of the URL is URLEncoded (IE: The path, the query, etc..)
    // The below if-statement allows us to search quoted strings - brave-ios/issues/1209.
    // - Brandon T.
    private static func validatedPunycodedURL(_ url: URL) -> URL? {
        // If there is no host/domain, we can't possibly validate that it was punycoded.
        // We'll return the original URL which can still be a valid relative or resource url
        // IE: "about:", "about:config", etc..
        if let host = url.host {
            guard let decodedASCIIURL = host.replacingOccurrences(of: "+", with: "").removingPercentEncoding else {
                return nil
            }
            
            if decodedASCIIURL.rangeOfCharacter(from: CharacterSet.URLAllowed.inverted) != nil {
                return nil
            }
        }
        
        return url
    }
    
    static func getURL(_ entry: String) -> URL? {
        let trimmed = entry.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let escaped = trimmed.addingPercentEncoding(withAllowedCharacters: .URLAllowed) else {
            return nil
        }

        // Then check if the URL includes a scheme. This will handle
        // all valid requests starting with "http://", "about:", etc.
        // However, we ensure that the scheme is one that is listed in
        // the official URI scheme list, so that other such search phrases
        // like "filetype:" are recognised as searches rather than URLs.
        if let url = punycodedURL(escaped), url.schemeIsValid {
            return validatedPunycodedURL(url)
        }

        // If there's no scheme, we're going to prepend "http://". First,
        // make sure there's at least one "." in the host. This means
        // we'll allow single-word searches (e.g., "foo") at the expense
        // of breaking single-word hosts without a scheme (e.g., "localhost").
        if trimmed.range(of: ".") == nil {
            return nil
        }

        if trimmed.range(of: " ") != nil {
            return nil
        }
        
        // A URL is only valid when the URL has a scheme, is not an email,
        // is not quoted, and can be punycoded.
        // If one of the above conditions is NOT satisfied,
        // the URL is invalid and should be deemed "search terms" instead.
        // Technically, an email is also a valid URL but does not get handled by the DNS server.
        // Instead, it is resolved in the search engine's resolver.
        //
        // The below if-statement fixes it by validating email.
        // The below if-statement allows us to search emails - brave-ios/issues/1209.
        // - Brandon T.
        if isValidEmail(escaped) {
            return nil
        }

        // If there is a ".", prepend "http://" and try again. Since this
        // is strictly an "http://" URL, we also require a host.
        if let url = punycodedURL("http://\(escaped)"), url.host != nil {
            return validatedPunycodedURL(url)
        }

        return nil
    }

    static func punycodedURL(_ string: String) -> URL? {
        var components = URLComponents(string: string)
        if AppConstants.MOZ_PUNYCODE {
            let host = components?.host?.utf8HostToAscii()
            components?.host = host
        }
        return components?.url
    }
    
    /// Checks whether a string is a valid email conforming to RFC 2822.
    /// http://www.cocoawithlove.com/2009/06/verifying-that-string-is-email-address.html
    static func isValidEmail(_ string: String) -> Bool {
        if string.isEmpty {
            return false
        }
        
        let regexRFC2822 =
            "(?:[a-zA-Z0-9!#$%\\&‘*+/=?\\^_`{|}~-]+(?:\\.[a-zA-Z0-9!#$%\\&'*+/=?\\^_`{|}" +
            "~-]+)*|\"(?:[\\x01-\\x08\\x0b\\x0c\\x0e-\\x1f\\x21\\x23-\\x5b\\x5d-\\" +
            "x7f]|\\\\[\\x01-\\x09\\x0b\\x0c\\x0e-\\x7f])*\")@(?:(?:[a-z0-9](?:[a-" +
            "z0-9-]*[a-z0-9])?\\.)+[a-z0-9](?:[a-z0-9-]*[a-z0-9])?|\\[(?:(?:25[0-5" +
            "]|2[0-4][0-9]|[01]?[0-9][0-9]?)\\.){3}(?:25[0-5]|2[0-4][0-9]|[01]?[0-" +
            "9][0-9]?|[a-z0-9-]*[a-z0-9]:(?:[\\x01-\\x08\\x0b\\x0c\\x0e-\\x1f\\x21" +
            "-\\x5a\\x53-\\x7f]|\\\\[\\x01-\\x09\\x0b\\x0c\\x0e-\\x7f])+)\\])"
        
        let relaxedRegexRFC2822 = "[a-z0-9!#$%&'*+/=?^_`{|}~-]+(?:\\.[a-z0-9!#$%&'*+/=?^_`{|}~-]+)*@(?:[a-z0-9](?:[a-z0-9-]*[a-z0-9])?\\.)+[a-z0-9](?:[a-z0-9-]*[a-z0-9])?"
        
        //return NSPredicate(format: "SELF MATCHES[c] %@", regex).evaluate(with: string)
        return string.range(of: regexRFC2822, options: .regularExpression) == string.startIndex..<string.endIndex || string.range(of: relaxedRegexRFC2822, options: .regularExpression) == string.startIndex..<string.endIndex
    }
}
