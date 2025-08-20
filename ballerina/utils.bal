// Copyright (c) 2025 WSO2 LLC (http://www.wso2.com).
//
// WSO2 LLC. licenses this file to you under the Apache License,
// Version 2.0 (the "License"); you may not use this file except
// in compliance with the License.
// You may obtain a copy of the License at
//
// http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing,
// software distributed under the License is distributed on an
// "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
// KIND, either express or implied.  See the License for the
// specific language governing permissions and limitations
// under the License.

import ballerina/ai;
import ballerina/regex;

isolated function deserializeSparseEmbedding(string embedding, int dimension) returns ai:SparseVector|error {
    int? indexOf = embedding.indexOf("}");
    string vector = embedding.substring(1, indexOf !is () ? indexOf : embedding.length() - 3);
    string[] parts = regex:split(vector, ",");
    int[] indices = from int index in 0 ... dimension
        select index;
    float[] values = [];
    foreach string part in parts {
        string[] indexValue = regex:split(part, ":");
        int index = check int:fromString(indexValue[0]);
        if indices.indexOf(index - 1) != () {
            _ = indices.remove(index - 1);
        }
        values.push(check float:fromString(indexValue[1]));
    }
    return {
        indices,
        values
    };
}

isolated function serializeSparseEmbedding(ai:SparseVector embedding, int dimension) returns string {
    string vector = "{";
    int count = 0;
    foreach int index in embedding.indices {
        float value = embedding.values[count];
        count += 1;
        int oneBasedIndex = index + 1;
        vector += string `${oneBasedIndex}:${value}`;
        if index != embedding.indices[embedding.indices.length() - 1] {
            vector += ",";
        }
    }
    vector += string `}/${dimension}`;
    return vector;
}

isolated function generateColumns(Column[] additionalColumns) returns string {
    if additionalColumns.length() == 0 {
        return "";
    }
    string joinedColumns = "";
    int colCount = additionalColumns.length();
    int index = 0;
    foreach Column column in additionalColumns {
        joinedColumns += string `${column.name} ${column.'type}`;
        index += 1;
        if index < colCount {
            joinedColumns += ", ";
        }
    }
    return joinedColumns;
}

isolated function generateOperator(ai:MetadataFilterOperator operator) returns string {
    match operator {
        ai:EQUAL => {
            return "=";
        }
        _ => {
            return operator;
        }
    }
}

isolated function generateFilter(ai:MetadataFilters|ai:MetadataFilter node) returns string {
    if node is ai:MetadataFilter {
        string operator = generateOperator(node.operator);
        json value = node.value;
        return string `${node.key} ${operator} ${value is string ? string `'${value}'` : value.toString()}`;
    }
    string condition = string ` ${node.condition.toString().toUpperAscii()} `;
    string[] filters = [];
    (ai:MetadataFilters|ai:MetadataFilter)[] children = node.filters;
    foreach (ai:MetadataFilters|ai:MetadataFilter) child in children {
        string expression = generateFilter(child);
        if expression.length() > 0 {
            filters.push(expression);
        }
    }
    if filters.length() == 0 {
        return "";
    }
    if filters.length() == 1 {
        return filters[0];
    }
    return combineElements(filters, condition);
}

isolated function combineElements(string[] filters, string condition) returns string {
    string combined = "";
    foreach string filter in filters {
        combined += filter;
        if filter != filters[filters.length() - 1] {
            combined += condition;
        }
    }
    return combined;
}
