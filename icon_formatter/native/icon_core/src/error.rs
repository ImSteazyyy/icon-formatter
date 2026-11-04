use thiserror::Error;

#[derive(Debug, Error)]
pub enum CoreError {
    #[error("cannot decode image: {0}")]
    Decode(String),
    #[error("cannot encode image: {0}")]
    Encode(String),
    #[error("I/O error: {0}")]
    Io(#[from] std::io::Error),
    #[error("ZIP error: {0}")]
    Zip(String),
    #[error("XML error: {0}")]
    Xml(String),
    #[error("invalid input: {0}")]
    Invalid(String),
    #[error("operation cancelled")]
    Cancelled,
}

impl From<zip::result::ZipError> for CoreError {
    fn from(e: zip::result::ZipError) -> Self {
        CoreError::Zip(e.to_string())
    }
}

impl From<image::ImageError> for CoreError {
    fn from(e: image::ImageError) -> Self {
        CoreError::Decode(e.to_string())
    }
}

pub type Result<T> = std::result::Result<T, CoreError>;
