using System.Collections;
using System.Collections.Generic;
using UnityEngine;

[System.AttributeUsage(System.AttributeTargets.Field, AllowMultiple = true)]
public class ConditionalPropertyAttribute : PropertyAttribute
{
    public string condition;

    public ConditionalPropertyAttribute(string condition)
    {
        this.condition = condition;
    }
}
