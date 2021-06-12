//			Copyright Brian Schott (Hackerpilot) 2012.
// Distributed under the Boost Software License, Version 1.0.
//	  (See accompanying file LICENSE_1_0.txt or copy at
//			http://www.boost.org/LICENSE_1_0.txt)

module dscanner.reports;

import std.json;
import std.algorithm : map;
import std.array : split, array, Appender, appender;

import dscanner.analysis.base : Message, MessageSet;
import dscanner.analysis.stats_collector;

class DScannerJsonReporter
{
	struct Issue
	{
		Message message;
		string type;
	}

	private Appender!(Issue[]) _issues;

	this()
	{
		_issues = appender!(Issue[]);
	}

	void addMessageSet(MessageSet messageSet)
	{
		_issues ~= toIssues(messageSet);
	}

	void addMessage(Message message, bool isError = false)
	{
		_issues ~= toIssue(message, isError);
	}

	string getContent(StatsCollector stats, ulong lineOfCodeCount)
	{
		JSONValue result = [
			"issues" : JSONValue(_issues.data.map!(e => toJson(e)).array),
			"interfaceCount": JSONValue(stats.interfaceCount),
			"classCount": JSONValue(stats.classCount),
			"functionCount": JSONValue(stats.functionCount),
			"templateCount": JSONValue(stats.templateCount),
			"structCount": JSONValue(stats.structCount),
			"statementCount": JSONValue(stats.statementCount),
			"lineOfCodeCount": JSONValue(lineOfCodeCount),
			"undocumentedPublicSymbols": JSONValue(stats.undocumentedPublicSymbols)
		];
		return result.toPrettyString();
	}

	private static JSONValue toJson(Issue issue)
	{
		// dfmt off
		JSONValue js = JSONValue([
			"key": JSONValue(issue.message.key),
			"fileName": JSONValue(issue.message.fileName),
			"line": JSONValue(issue.message.line),
			"column": JSONValue(issue.message.column),
			"message": JSONValue(issue.message.message),
			"type": JSONValue(issue.type)
		]);
		// dfmt on

		if (issue.message.checkName !is null)
		{
			js["name"] = JSONValue(issue.message.checkName);
		}

		return js;
	}

	private static Issue[] toIssues(MessageSet messageSet)
	{
		return messageSet[].map!(e => toIssue(e)).array;
	}

	private static Issue toIssue(Message message, bool isError = false)
	{
		// dfmt off
		Issue issue = {
			message: message,
			type : isError ? "error" : "warn"
		};
		// dfmt on
		return issue;
	}
}

class SonarQubeGenericIssueDataReporter
{
	enum Type
	{
		bug = "BUG",
		vulnerability = "VULNERABILITY",
		codeSmell = "CODE_SMELL"
	}

	enum Severity
	{
		blocker = "BLOCKER",
		critical = "CRITICAL",
		major = "MAJOR",
		minor = "MINOR",
		info = "INFO"
	}

	struct Issue
	{
		string engineId;
		string ruleId;
		Location primaryLocation;
		string type;
		string severity;
		int effortMinutes;
		Location[] secondaryLocations;
	}

	struct Location
	{
		string message;
		string filePath;
		TextRange textRange;
	}

	struct TextRange
	{
		// SonarQube Generic Issue only allows specifying start line only
		// or the complete range, for which start and end has to differ
		// D-Scanner does not provide the complete range info
		long startLine;
	}

	private Appender!(Issue[]) _issues;

	this()
	{
		_issues = appender!(Issue[]);
	}

	void addMessageSet(MessageSet messageSet)
	{
		_issues ~= toIssues(messageSet);
	}
	
	void addMessage(Message message, bool isError = false)
	{
		_issues ~= toIssue(message, isError);
	}

	string getContent()
	{
		JSONValue result = [
			"issues" : JSONValue(_issues.data.map!(e => toJson(e)).array)
		];
		return result.toPrettyString();
	}

	private static JSONValue toJson(Issue issue)
	{
		// dfmt off
		return JSONValue([
			"engineId": JSONValue(issue.engineId),
			"ruleId": JSONValue(issue.ruleId),
			"severity": JSONValue(issue.severity),
			"type": JSONValue(issue.type),
			"primaryLocation": JSONValue([
				"message": JSONValue(issue.primaryLocation.message),
				"filePath": JSONValue(issue.primaryLocation.filePath),
				"textRange": JSONValue([
					"startLine": JSONValue(issue.primaryLocation.textRange.startLine)
				]),
			]),
		]);
		// dfmt on
	}

	private static Issue[] toIssues(MessageSet messageSet)
	{
		return messageSet[].map!(e => toIssue(e)).array;
	}

	private static Issue toIssue(Message message, bool isError = false)
	{		
		// dfmt off
		Issue issue = {
			engineId: "dscanner",
			ruleId : message.key,
			severity : (isError) ? Severity.blocker : getSeverity(message.key),
			type : getType(message.key),
			primaryLocation : getPrimaryLocation(message)
		};
		// dfmt on
		return issue;
	}

	private static Location getPrimaryLocation(Message message)
	{
		return Location(message.message, message.fileName, TextRange(message.line));
	}

	private static string getSeverity(string key)
	{
		auto a = key.split(".");

		if (a.length <= 1)
		{
			return Severity.major;
		}
		else
		{
			switch (a[1])
			{
				case "style":
					return Severity.minor;
				default:
					return Severity.major;
			}
		}
	}

	private static string getType(string key)
	{
		auto a = key.split(".");

		if (a.length <= 1)
		{
			return Type.bug;
		}
		else
		{
			switch (a[1])
			{
				case "style":
					return Type.codeSmell;
				default:
					return Type.bug;
			}
		}
	}
}

class CodeClimateGenericIssueDataReporter
{
	enum Type
	{
		bug = "Bug Risk",
		vulnerability = "Security",
		codeSmell = "Style"
	}

	enum Severity
	{
		blocker = "blocker",
		critical = "critical",
		major = "major",
		minor = "minor",
		info = "info"
	}

	struct Issue
	{
		string type;
		string check_name;
		string description;
		string content;
		string[] categories;
		Location location;
		int remediation_points;
		string severity;
	}

	struct Location
	{
		string path;
		size_t line;
		size_t column;
	}

	private Appender!(Issue[]) _issues;

	this()
	{
		_issues = appender!(Issue[]);
	}

	void addMessageSet(MessageSet messageSet)
	{
		_issues ~= toIssues(messageSet);
	}

	void addMessage(Message message, bool isError = false)
	{
		_issues ~= toIssue(message, isError);
	}

	string getContent()
	{
		JSONValue result = JSONValue(_issues.data.map!(e => toJson(e)).array);
		return result.toPrettyString();
	}

	private static JSONValue toJson(Issue issue)
	{
		// dfmt off
		return JSONValue([
			"type": JSONValue("issue"),
			"check_name": JSONValue(issue.check_name),
			"description": JSONValue(issue.description),
			"content": JSONValue(["body": issue.content]),
			"categories": JSONValue(issue.categories.map!(c => JSONValue(c)).array),
			"location": JSONValue([
				"path": JSONValue(issue.location.path),
				"lines": JSONValue([
					"begin": JSONValue([
						"line": JSONValue(issue.location.line),
						"column": JSONValue(issue.location.column)
					])
				]),
			]),
			// "remediation_points": JSONValue(issue.remediation_points),
			"severity": JSONValue(issue.severity)
		]);
		// dfmt on
	}

	private static Issue[] toIssues(MessageSet messageSet)
	{
		return messageSet[].map!(e => toIssue(e)).array;
	}

	private static Issue toIssue(Message message, bool isError = false)
	{
		// dfmt off
		Issue issue = {
			type : "issue",
			check_name : message.checkName,
			description : message.message,
			content : message.key,
			categories : getCategories(message.key),
			severity : (isError) ? Severity.blocker : getSeverity(message.key),
			location : getPrimaryLocation(message)
		};
		// dfmt on
		return issue;
	}

	private static Location getPrimaryLocation(Message message)
	{
		return Location(message.fileName, message.line, message.column);
	}

	private static string getSeverity(string key)
	{
		auto a = key.split(".");

		if (a.length <= 1)
		{
			return Severity.major;
		}
		else
		{
			switch (a[1])
			{
				case "style":
					return Severity.minor;
				default:
					return Severity.major;
			}
		}
	}

	private static string[] getCategories(string key)
	{
		auto a = key.split(".");

		if (a.length <= 1)
		{
			return [Type.bug];
		}
		else
		{
			switch (a[1])
			{
				case "style":
					return [Type.codeSmell];
				default:
					return [Type.bug];
			}
		}
	}
}
