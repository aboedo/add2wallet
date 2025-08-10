import Foundation

struct PassDateTimeFormatter {
    
    /// Combines date and time strings intelligently with proper localization
    /// Uses the more sophisticated approach from SavedPassDetailView
    static func combineDateTime(date: String?, time: String?) -> String? {
        let cleanDate = date?.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanTime = time?.trimmingCharacters(in: .whitespacesAndNewlines)
        if (cleanDate?.isEmpty ?? true) && (cleanTime?.isEmpty ?? true) { return nil }
        
        let cal = Calendar.autoupdatingCurrent
        
        // Parse fixed-format date
        var dateObj: Date?
        if let ds = cleanDate, !ds.isEmpty {
            let iso = DateFormatter()
            iso.calendar = cal
            iso.locale = Locale(identifier: "en_US_POSIX")
            iso.dateFormat = "yyyy-MM-dd"
            dateObj = iso.date(from: ds)
        }
        
        // Parse fixed-format time
        var timeComponents: DateComponents?
        if let ts = cleanTime, !ts.isEmpty {
            let tf = DateFormatter()
            tf.calendar = cal
            tf.locale = Locale(identifier: "en_US_POSIX")
            tf.dateFormat = "HH:mm"
            if let tDate = tf.date(from: ts) {
                timeComponents = cal.dateComponents([.hour, .minute, .second], from: tDate)
            }
        }
        
        // Format combined output in user locale
        let output = DateFormatter()
        output.calendar = cal
        output.locale = .autoupdatingCurrent
        output.dateStyle = (dateObj != nil) ? .short : .none
        output.timeStyle = (timeComponents != nil) ? .short : .none
        output.doesRelativeDateFormatting = true
        
        if let d = dateObj, let t = timeComponents,
           let combined = cal.date(bySettingHour: t.hour ?? 0,
                                   minute: t.minute ?? 0,
                                   second: t.second ?? 0,
                                   of: d) {
            return output.string(from: combined)
        }
        
        if let d = dateObj {
            return output.string(from: d)
        }
        
        if let t = timeComponents {
            let today = cal.startOfDay(for: Date())
            if let dt = cal.date(bySettingHour: t.hour ?? 0,
                                 minute: t.minute ?? 0,
                                 second: t.second ?? 0,
                                 of: today) {
                output.dateStyle = .none
                output.timeStyle = .short
                return output.string(from: dt)
            }
        }
        
        return nil
    }
    
    /// Simple version for basic date/time combination (used as fallback)
    static func simpleCombineDateTime(date: String?, time: String?) -> String? {
        let cleanDate = date?.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanTime = time?.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if let date = cleanDate, !date.isEmpty, let time = cleanTime, !time.isEmpty {
            return "\(date) at \(time)"
        } else if let date = cleanDate, !date.isEmpty {
            return date
        } else if let time = cleanTime, !time.isEmpty {
            return time
        } else {
            return nil
        }
    }
    
    /// Format event date string with various input formats (from SavedPassesView)
    static func formatEventDate(_ eventDateString: String) -> String {
        // Try to parse the event date string and reformat it consistently
        let inputFormatters = [
            "MMM d, yyyy 'at' h:mm a",  // "Dec 15, 2024 at 8:00 PM"
            "MMM d, yyyy h:mm a",       // "Dec 15, 2024 8:00 PM"
            "MMMM d, yyyy 'at' h:mm a", // "December 15, 2024 at 8:00 PM"
            "MMMM d, yyyy h:mm a",      // "December 15, 2024 8:00 PM"
            "MMM d, yyyy",              // "Dec 15, 2024"
            "MMMM d, yyyy",             // "December 15, 2024"
            "MM/dd/yyyy",               // "12/15/2024"
            "dd/MM/yyyy",               // "15/12/2024"
            "yyyy-MM-dd",               // "2024-12-15"
            "d MMMM yyyy",              // "15 December 2024"
            "MMM d",                    // "Dec 15" (current year assumed)
            "MMMM d"                    // "December 15" (current year assumed)
        ]
        
        for formatString in inputFormatters {
            let formatter = DateFormatter()
            formatter.dateFormat = formatString
            if let parsedDate = formatter.date(from: eventDateString) {
                // Return in localized format with both date and time if available
                let outputFormatter = DateFormatter()
                outputFormatter.dateStyle = .short
                // Check if the original string contained time information
                let hasTime = eventDateString.lowercased().contains("am") || 
                             eventDateString.lowercased().contains("pm") ||
                             eventDateString.contains(":") ||
                             eventDateString.lowercased().contains("at")
                outputFormatter.timeStyle = hasTime ? .short : .none
                return outputFormatter.string(from: parsedDate)
            }
        }
        
        // If we can't parse it, return the original string
        return eventDateString
    }
    
    /// Format date in localized short format (from SavedPassesView)
    static func formatDateLocalized(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
