using System.Collections;
using System.Collections.Generic;
using UnityEngine;

public class WaterSpawner : MonoBehaviour
{    
    public GameObject waterSystem;
    [SerializeField]
    private float _Speed = 0.5f;
    [SerializeField]
    private float _WaterTargetHeight = 1f;

    Rigidbody rigidBody;
    bool mouseDown = false;

    private void Awake()
    {
        rigidBody = GetComponent<Rigidbody>();
    }

    void OnMouseDown()
    {
        mouseDown = true;
    }

    private void Update()
    {
        if(mouseDown && waterSystem.transform.position.y <= _WaterTargetHeight)
        {            
            waterSystem.transform.position = new Vector3(waterSystem.transform.position.x,
                                                        waterSystem.transform.position.y + Time.deltaTime * _Speed,
                                                        waterSystem.transform.position.z);  
        }

    }
}