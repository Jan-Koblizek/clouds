using System.Collections;
using System.Collections.Generic;
using UnityEngine;

public class SunShafts : MonoBehaviour
{
    private Material sunShaftsMaterial;
    public Transform sunTransform;
    public Color sunShaftsColor = new Color(1.0f, 1.0f, 1.0f, 1.0f);
    public float sunShaftsStrength = 1.0f;

    private void Start()
    {
        sunShaftsMaterial = (UnityEngine.Material)Resources.Load("Clouds/SunShaftsMaterial");
    }
    private void OnRenderImage(RenderTexture source, RenderTexture destination)
    {
        RenderTexture tmpBuffer = RenderTexture.GetTemporary(source.width, source.height, 0);
        RenderTexture.active = tmpBuffer;
        GL.ClearWithSkybox(false, GetComponent<Camera>());

        sunShaftsMaterial.SetTexture("_Skybox", tmpBuffer);
        RenderTexture sunShaftsBuffer = RenderTexture.GetTemporary(source.width / 2, source.height / 2, 0);
        RenderTexture sunShaftsBuffer2;
        sunShaftsMaterial.SetVector("_SunColor", sunShaftsColor);
        
        Vector3 v = Vector3.one * 0.5f;
        //Get position of the sun dot
        if (sunTransform)
            v = GetComponent<Camera>().WorldToViewportPoint(this.transform.position - sunTransform.forward * 10000);

        float basicBlurRadius = 1.0f / 40.0f;
        float blur = basicBlurRadius;
        sunShaftsMaterial.SetVector("_SunPosition", new Vector4(v.x, v.y, v.z, 0.75f));
        sunShaftsMaterial.SetVector("_Blur", new Vector4(blur, blur, 0.0f, 0.0f));
        sunShaftsMaterial.SetFloat("_ShaftsStrength", sunShaftsStrength);
        //Select unobstructed sky
        Graphics.Blit(source, sunShaftsBuffer, sunShaftsMaterial, 0);

        //Bluring the light in the direction away from the sun dot
        for (int i = 0; i < 2; i++)
        {
            sunShaftsBuffer2 = RenderTexture.GetTemporary(source.width / 2, source.height / 2, 0);
            Graphics.Blit(sunShaftsBuffer, sunShaftsBuffer2, sunShaftsMaterial, 1);
            RenderTexture.ReleaseTemporary(sunShaftsBuffer);
            blur = basicBlurRadius * (((i * 2.0f + 1.0f) * 6.0f));
            sunShaftsMaterial.SetVector("_BlurRadius4", new Vector4(blur, blur, 0.0f, 0.0f));

            sunShaftsBuffer = RenderTexture.GetTemporary(source.width / 2, source.height / 2, 0);
            Graphics.Blit(sunShaftsBuffer2, sunShaftsBuffer, sunShaftsMaterial, 1);
            RenderTexture.ReleaseTemporary(sunShaftsBuffer2);
            blur = basicBlurRadius * (((i * 2.0f + 2.0f) * 6.0f));
            sunShaftsMaterial.SetVector("_BlurRadius4", new Vector4(blur, blur, 0.0f, 0.0f));
        }

        sunShaftsMaterial.SetTexture("_ColorBuffer", sunShaftsBuffer);
        //Add shafts to the image
        Graphics.Blit(source, destination, sunShaftsMaterial, 2);

        RenderTexture.ReleaseTemporary(sunShaftsBuffer);
        RenderTexture.ReleaseTemporary(tmpBuffer);
    }
}
