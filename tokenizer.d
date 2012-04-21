
//          Copyright Brian Schott (Sir Alaran) 2012.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)

module tokenizer;

import std.range;
import std.file;
import std.traits;
import std.algorithm;
import std.conv;
import std.uni;
import std.stdio;

import langutils;
import codegen;


/**
 * Increments endIndex until it indexes a non-whitespace character in
 * inputString.
 * Params:
 *     inputString = the source code to examine
 *     endIndex = an index into inputString
 *     lineNumber = the line number that corresponds to endIndex
 *     style = the code iteration style
 * Returns: The whitespace, or null if style was CODE_ONLY
 */
pure nothrow string lexWhitespace(S)(S inputString, ref size_t endIndex,
	ref uint lineNumber, IterationStyle style = IterationStyle.CODE_ONLY)
	if (isSomeString!S)
{
	immutable startIndex = endIndex;
	while (endIndex < inputString.length && isWhite(inputString[endIndex]))
	{
		if (inputString[endIndex] == '\n')
			lineNumber++;
		++endIndex;
	}
	final switch (style)
	{
	case IterationStyle.EVERYTHING:
		return inputString[startIndex .. endIndex];
	case IterationStyle.CODE_ONLY:
		return null;
	}
}


/**
 * Increments endIndex until it indexes a character directly after a comment
 * Params:
 *     inputString = the source code to examine
 *     endIndex = an index into inputString at the second character of a
 *     comment, i.e. points at the second slash in a // comment.
 *     lineNumber = the line number that corresponds to endIndex
 * Returns: The comment
 */
pure nothrow string lexComment(S)(ref S inputString, ref size_t endIndex,
	ref uint lineNumber) if (isSomeString!S)
{
	if (inputString.length == 0)
		return "";
	auto startIndex = endIndex - 1;
	switch(inputString[endIndex])
	{
	case '/':
		while (endIndex < inputString.length && inputString[endIndex] != '\n')
		{
			if (inputString[endIndex] == '\n')
				++lineNumber;
			++endIndex;
		}
		break;
	case '*':
		while (endIndex < inputString.length
			&& !inputString[endIndex..$].startsWith("*/"))
		{
			if (inputString[endIndex] == '\n')
				++lineNumber;
			++endIndex;
		}
		endIndex += 2;
		break;
	case '+':
		++endIndex;
		int depth = 1;
		while (depth > 0 && endIndex + 1 < inputString.length)
		{
			if (inputString[endIndex] == '\n')
				lineNumber++;
			else if (inputString[endIndex..$].startsWith("+/"))
				depth--;
			else if (inputString[endIndex..$].startsWith("/+"))
				depth++;
			++endIndex;
		}
		++endIndex;
		break;
	default:
		break;
	}
	return inputString[startIndex..endIndex];
}


/**
 * Params:
 *     inputString = the source code to examine
 *     endIndex = an index into inputString at the opening quote
 *     lineNumber = the line number that corresponds to endIndex
 *     quote = the opening (and closing) quote character for the string to be
 *         lexed
 * Returns: a string literal, including its opening and closing quote characters
 * Bugs: Does not handle string suffixes
 */
pure nothrow string lexString(S, C)(S inputString, ref size_t endIndex, ref uint lineNumber,
	C quote, bool canEscape = true) if (isSomeString!S && isSomeChar!C)
in
{
	assert (inputString[endIndex] == quote);
	assert (quote == '\'' || quote == '\"' || quote == '`');
}
body
{
	if (inputString[endIndex] != quote)
		return "";
	auto startIndex = endIndex;
	++endIndex;
	bool escape = false;
	while (endIndex < inputString.length && (inputString[endIndex] != quote || escape))
	{
		if (escape)
			escape = false;
		else
			escape = (canEscape && inputString[endIndex] == '\\');
		if (inputString[endIndex] == '\n')
			lineNumber++;
		++endIndex;
	}
	++endIndex;
	endIndex = min(endIndex, inputString.length);
	return inputString[startIndex .. endIndex];
}


/**
 * Lexes the various crazy D string literals such as q{}, q"WTF is this? WTF",
 * and q"<>".
 * Params:
 *     inputString = the source code to examine
 *     endIndex = an index into inputString at the opening quote
 *     lineNumber = the line number that corresponds to endIndex
 * Returns: a string literal, including its opening and closing quote characters
 */
string lexDelimitedString(S)(ref S inputString, ref size_t endIndex,
	ref uint lineNumber) if (isSomeString!S)
{
	auto startIndex = endIndex;
	++endIndex;
	string open = to!string(inputString[endIndex]);
	string close;
	bool nesting = false;
	switch (open)
	{
	case "[": close = "]"; ++endIndex; nesting = true; break;
	case "<": close = ">"; ++endIndex; nesting = true; break;
	case "{": close = "}"; ++endIndex; nesting = true; break;
	case "(": close = ")"; ++endIndex; nesting = true; break;
	default:
		while(!isWhite(inputString[endIndex])) endIndex++;
		close = open = inputString[startIndex + 1 .. endIndex];
		break;
	}
	int depth = 1;
	while (endIndex < inputString.length && depth > 0)
	{
		if (inputString[endIndex] == '\n')
		{
			lineNumber++;
			endIndex++;
		}
		else if (inputString[endIndex..$].startsWith(open))
		{
			endIndex += open.length;
			if (!nesting)
			{
				if (inputString[endIndex] == '\"')
					++endIndex;
				break;
			}
			depth++;
		}
		else if (inputString[endIndex..$].startsWith(close))
		{
			endIndex += close.length;
			depth--;
			if (depth <= 0)
				break;
		}
		else
			++endIndex;
	}
	if (endIndex < inputString.length && inputString[endIndex] == '\"')
		++endIndex;
	return inputString[startIndex .. endIndex];
}


string lexTokenString(S)(ref S inputString, ref size_t endIndex, ref uint lineNumber)
{
	/+auto r = byDToken(range, IterationStyle.EVERYTHING);
	string s = getBraceContent(r);
	range.popFrontN(s.length);
	return s;+/
	return "";
}

/**
 *
 */
pure nothrow string lexNumber(S)(ref S inputString, ref size_t endIndex) if (isSomeString!S)
{
	auto startIndex = endIndex;
	bool foundDot = false;
	bool foundX = false;
	bool foundB = false;
	bool foundE = false;
	numberLoop: while (endIndex < inputString.length)
	{
		switch (inputString[endIndex])
		{
		case '0':
			if (!foundX)
			{
				++endIndex;
				if (endIndex < inputString.length
					&& (inputString[endIndex] == 'x' || inputString[endIndex] == 'X'))
				{
					++endIndex;
					foundX = true;
				}
			}
			else
				++endIndex;
			break;
		case 'b':
			if (foundB)
				break numberLoop;
			foundB = true;
			++endIndex;
			break;
		case '.':
			if (foundDot || foundX || foundE)
				break numberLoop;
			foundDot = true;
			++endIndex;
			break;
		case '+':
		case '-':
			if (!foundE)
				break numberLoop;
			++endIndex;
			break;
		case 'p':
		case 'P':
			if (!foundX)
				break numberLoop;
			foundE = true;
			goto case '_';
		case 'e':
		case 'E':
			if (foundE || foundX)
				break numberLoop;
			foundE = true;
			goto case '_';
		case '1': .. case '9':
		case '_':
			++endIndex;
			break;
		case 'F':
		case 'f':
		case 'L':
		case 'i':
			++endIndex;
			break numberLoop;
		default:
			break numberLoop;
		}
	}
	return inputString[startIndex .. endIndex];
}


/**
 * Returns: true if  ch marks the ending of one token and the beginning of
 *     another, false otherwise
 */
pure nothrow bool isSeparating(C)(C ch) if (isSomeChar!C)
{
	switch (ch)
	{
		case '!': .. case '/':
		case ':': .. case '@':
		case '[': .. case '^':
		case '{': .. case '~':
		case 0x20: // space
		case 0x09: // tab
		case 0x0a: .. case 0x0d: // newline, vertical tab, form feed, carriage return
			return true;
		default:
			return false;
	}
}

/**
 * Configure the tokenize() function
 */
enum IterationStyle
{
	/// Only include code, not whitespace or comments
	CODE_ONLY,
	/// Include everything
	EVERYTHING
}

Token[] tokenize(S)(S inputString, IterationStyle iterationStyle = IterationStyle.CODE_ONLY)
	if (isSomeString!S)
{
	auto tokenAppender = appender!(Token[])();

	// This is very likely a local maximum, but it does seem to take a few
	// milliseconds off of the run time
	tokenAppender.reserve(inputString.length / 4);

	size_t endIndex = 0;
	uint lineNumber = 1;
	while (endIndex < inputString.length)
	{
		Token currentToken;
		auto startIndex = endIndex;
		if (isWhite(inputString[endIndex]))
		{
			if (iterationStyle == IterationStyle.EVERYTHING)
			{
				currentToken.lineNumber = lineNumber;
				currentToken.value = lexWhitespace(inputString, endIndex,
					lineNumber, IterationStyle.EVERYTHING);
				currentToken.type = TokenType.whitespace;
				tokenAppender.put(currentToken);
			}
			else
				lexWhitespace(inputString, endIndex, lineNumber);
			continue;
		}
		currentToken.startIndex = endIndex;

		outerSwitch: switch(inputString[endIndex])
		{
		mixin(generateCaseTrie(
			"=",    "TokenType.assign",
			"&",    "TokenType.bitAnd",
			"&=",   "TokenType.bitAndEquals",
			"|",    "TokenType.bitOr",
			"|=",   "TokenType.bitOrEquals",
			"~=",   "TokenType.catEquals",
			":",    "TokenType.colon",
			",",    "TokenType.comma",
			"$",    "TokenType.dollar",
			".",    "TokenType.dot",
			"==",   "TokenType.equals",
			"=>",   "TokenType.goesTo",
			">",    "TokenType.greater",
			">=",   "TokenType.greaterEqual",
			"#",    "TokenType.hash",
			"&&",   "TokenType.lAnd",
			"{",    "TokenType.lBrace",
			"[",    "TokenType.lBracket",
			"<",    "TokenType.less",
			"<=",   "TokenType.lessEqual",
			"<>=",  "TokenType.lessEqualGreater",
			"<>",   "TokenType.lessOrGreater",
			"||",   "TokenType.lOr",
			"(",    "TokenType.lParen",
			"-",    "TokenType.minus",
			"-=",   "TokenType.minusEquals",
			"%",    "TokenType.mod",
			"%=",   "TokenType.modEquals",
			"*=",   "TokenType.mulEquals",
			"!",    "TokenType.not",
			"!=",   "TokenType.notEquals",
			"!>",   "TokenType.notGreater",
			"!>=",  "TokenType.notGreaterEqual",
			"!<",   "TokenType.notLess",
			"!<=",  "TokenType.notLessEqual",
			"!<>",  "TokenType.notLessEqualGreater",
			"+",    "TokenType.plus",
			"+=",   "TokenType.plusEquals",
			"^^",   "TokenType.pow",
			"^^=",  "TokenType.powEquals",
			"}",    "TokenType.rBrace",
			"]",    "TokenType.rBracket",
			")",    "TokenType.rParen",
			";",    "TokenType.semicolon",
			"<<",   "TokenType.shiftLeft",
			"<<=",  "TokenType.shiftLeftEqual",
			">>",   "TokenType.shiftRight",
			">>=",  "TokenType.shiftRightEqual",
			"..",   "TokenType.slice",
			"*",    "TokenType.star",
			"?",    "TokenType.ternary",
			"~",    "TokenType.tilde",
			"--",   "TokenType.uMinus",
			"!<>=", "TokenType.unordered",
			">>>",  "TokenType.unsignedShiftRight",
			">>>=", "TokenType.unsignedShiftRightEqual",
			"++",   "TokenType.uPlus",
			"...",  "TokenType.vararg",
			"^",    "TokenType.xor",
			"^=",   "TokenType.xorEquals",
		));

		case '0': .. case '9':
			currentToken.value = lexNumber(inputString, endIndex);
			currentToken.type = TokenType.numberLiteral;
			currentToken.lineNumber = lineNumber;
			break;
		case '/':
			++endIndex;
			if (endIndex >= inputString.length)
			{
				currentToken.value = "/";
				currentToken.type = TokenType.div;
				currentToken.lineNumber = lineNumber;
				break;
			}
			currentToken.lineNumber = lineNumber;
			switch (inputString[endIndex])
			{
			case '/':
			case '+':
			case '*':
				if (iterationStyle == IterationStyle.CODE_ONLY)
				{
					lexComment(inputString, endIndex, lineNumber);
					continue;
				}
				else
				{
					currentToken.value = lexComment(inputString, endIndex, lineNumber);
					currentToken.type = TokenType.comment;
					break;
				}
			case '=':
				currentToken.value = "/=";
				currentToken.type = TokenType.divEquals;
				++endIndex;
				break;
			default:
				currentToken.value = "/";
				currentToken.type = TokenType.div;
				break;
			}
			break;
		case 'r':
			currentToken.value = "r";
			++endIndex;
			if (inputString[endIndex] == '\"')
			{
				currentToken.lineNumber = lineNumber;
				currentToken.value = lexString(inputString, endIndex,
					lineNumber, inputString[endIndex], false);
				currentToken.type = TokenType.stringLiteral;
				break;
			}
			else
				goto default;
		case '`':
			currentToken.lineNumber = lineNumber;
			currentToken.value = lexString(inputString, endIndex, lineNumber,
				inputString[endIndex], false);
			currentToken.type = TokenType.stringLiteral;
			break;
		case 'x':
			currentToken.value = "x";
			++endIndex;
			if (inputString[endIndex] == '\"')
				goto case '\"';
			else
				goto default;
		case '\'':
		case '"':
			currentToken.lineNumber = lineNumber;
			currentToken.value = lexString(inputString, endIndex, lineNumber,
				inputString[endIndex]);
			currentToken.type = TokenType.stringLiteral;
			break;
		case 'q':
			++endIndex;
			switch (inputString[endIndex])
			{
				case '\"':
					currentToken.lineNumber = lineNumber;
					currentToken.value ~= "q" ~ lexDelimitedString(inputString,
						endIndex, lineNumber);
					currentToken.type = TokenType.stringLiteral;
					break outerSwitch;
				case '{':
					currentToken.lineNumber = lineNumber;
					currentToken.value ~= "q" ~ lexTokenString(inputString,
						endIndex, lineNumber);
					currentToken.type = TokenType.stringLiteral;
					break outerSwitch;
				default:
					break;
			}
			goto default;
		case '@':
			++endIndex;
			goto default;
		default:
			while(endIndex < inputString.length && !isSeparating(inputString[endIndex]))
				++endIndex;
			currentToken.value = inputString[startIndex .. endIndex];
			currentToken.type = lookupTokenType(currentToken.value);
			currentToken.lineNumber = lineNumber;
			break;
		}
//		writeln(currentToken);
		tokenAppender.put(currentToken);
	}
	return tokenAppender.data;
}
